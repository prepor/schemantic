require 'uri'
module Schemantic
  VERSION = "0.4.0"
  class Context
    attr_reader :errors
    def self.parse(data)
      new.parse(data)
    end

    def self.validate(schema, data)
      schema.context.validate(schema, data)
    end

    attr_reader :internal_uri
    def initialize
      @errors = []
      @mapping = {}
      @internal_uri = URI.parse('http://localhost/')
    end

    def resolve_ref(ref_uri)
      get_mapping ref_uri
    end

    def set_mapping(uri, schema)
      @mapping[uri.to_s] ||= schema
    end

    def get_mapping(uri)
      try_mapping(uri) || external_ref(uri)
    end

    def try_mapping(uri)
      @mapping[uri.to_s] || relative_mapping(uri)
    end

    def relative_mapping(uri)
      uri = uri.dup
      fragment = uri.fragment
      return nil if fragment.nil? || !valid_json_pointer?(fragment)
      uri.fragment = ''
      m = @mapping[uri.to_s]
      return nil unless m
      resolve_json_pointer(m, fragment)
    end

    # FIXME real validator
    def valid_json_pointer?(fragment)
      fragment[0,1] == '/'
    end

    def resolve_json_pointer(schema, pointer)
      data = schema
      fragments = pointer.split('/')
      fragments[1, fragments.size].each do |p|
        data = case data
               when Schema
                 data.tree[p]
               when Array
                 data[p.to_i]
               when Hash
                 data[p]
               when nil
                 nil
               end
      end
      data
    end

    def external_ref(ref)
      return nil unless @on_external_ref
      res = @on_external_ref.call ref
      if res
        ref.fragment ||= '' # root element always has empty fragment
        ref_without_fragment = ref.dup.tap { |o| o.fragment = '' }
        with_internal_uri(ref_without_fragment) do
          parse(res)
        end
        try_mapping(ref)
      else
        nil
      end
    end

    def on_external_ref(&clb)
      @on_external_ref = clb
    end

    def set_internal_uri(uri_str)
      @internal_uri = URI.parse uri_str
    end

    def with_internal_uri(uri)
      old, @internal_uri = @internal_uri, uri
      yield
    ensure
      @internal_uri = old
    end

    def parse(data, parent = nil)
      if data['$ref']
        RefSchema.new(self, parent, data['$ref'])
      else
        Schema.new(self, parent).parse(data)
      end
    end

    def validate(schema, data)
      @errors = []
      schema.validate(data)
    end
  end

  class Validator
    def self.new_and_parse(schema, data)
      new schema, parse(schema, data)
    end
    attr_reader :schema, :value
    def initialize(schema, value)
      @schema, @value = schema, value
    end

    def validate(obj)

    end

    def without_errors(&blk)
      origin_errors = schema.context.errors.dup
      blk.call
    ensure
      schema.context.errors.replace origin_errors
    end

    def error(path)
      schema.context.errors << { path: path, validator: self.class, params: value }
      false
    end

    def value_or(name, default)
      if validator = schema.tree[name]
        validator.value
      else
        default
      end
    end
  end


  module Validators
    module PureValue
      def parse(schema, value)
        value
      end
    end

    module SimpleBoolCheck
      def validate(obj, path)
        res = bool_check(obj)
        unless res
          error path
        end
        res
      end
    end

    class Type < Validator
      extend PureValue
      include SimpleBoolCheck
      MAPPING = {
        'string' => String,
        'integer' => Integer,
        'number' => Numeric,
        'null' => NilClass,
        'boolean' => [TrueClass, FalseClass],
        'object' => Hash,
        'array' => Array
      }

      def same_type?(t, v)
        types = MAPPING[t]
        if types.is_a?(Array)
          !!types.find { |t| v.is_a?(t) }
        else
          v.is_a?(types)
        end
      end

      def bool_check(obj)
        if value.is_a?(Array)
          !!value.find { |v| same_type?(v, obj) }
        else
          same_type?(value, obj)
        end
      end
    end

    module OfValidators
      attr_reader :schemas
      def self.included(base)
        base.extend(ClassMethods)
      end
      module ClassMethods
        def parse(schema, value)
          value.map { |v| schema.schema(v) }
        end
      end

      def validate(obj, path)
        res = without_errors do
          value.select { |v| v.validate(obj, path) }
        end
        if predicat(res.size)
          true
        else
          error path
        end
      end
    end

    class OneOf < Validator
      include OfValidators

      def predicat(res_size)
        res_size == 1
      end
    end

    class AnyOf < Validator
      include OfValidators
      def predicat(res_size)
        res_size > 0
      end
    end

    class AllOf < Validator
      include OfValidators

      def predicat(res_size)
        res_size == value.size
      end
    end

    class Dependencies < Validator
      def self.parse(schema, value)
        value.map do |k, v|
          [k, v.is_a?(Array) ? v : schema.schema(v)]
        end
      end

      def validate(obj, path)
        res = value.select do |k, v|
          if obj.key?(k)
            if v.is_a?(Array)
              res = v.all? { |dependency_prop| obj.key? dependency_prop }
              unless res
                error path
              end
              res
            else
              v.validate(obj, path)
            end
          else
            true
          end
        end
        res.size == value.size
      end
    end

    class Maximum < Validator
      extend PureValue
      include SimpleBoolCheck
      def bool_check(obj)
        predicat = schema.tree['exclusiveMaximum'] == true ? :< : :<=
          obj.send(predicat, value)
      end
    end

    class Minimum < Validator
      extend PureValue
      include SimpleBoolCheck

      def bool_check(obj)
        predicat = schema.tree['exclusiveMinimum'] == true ? :> : :>=
          obj.send(predicat, value)
      end
    end

    class MaxLength < Validator
      extend PureValue
      include SimpleBoolCheck
      def bool_check(obj)
        obj.size <= value
      end
    end

    class MinLength < Validator
      extend PureValue
      include SimpleBoolCheck
      def bool_check(obj)
        obj.size >= value
      end
    end

    class Required < Validator
      extend PureValue

      def validate(obj, path)
        res = (value - obj.keys)
        res.each do |k|
          error path
        end
        res.size == 0
      end
    end

    class Enum < Validator
      extend PureValue

      def validate(obj, path)
        res = value.include?(obj)
        error path unless res
        res
      end
    end

    class Not < Validator
      def self.parse(schema, data)
        schema.schema(data)
      end

      def validate(obj, path)
        res = without_errors do
          value.validate(obj, path)
        end
        !res
      end
    end

    class MultipleOf < Validator
      extend PureValue
      include SimpleBoolCheck

      def bool_check(obj)
        obj % value == 0
      end
    end

    module CheckProperties
      def self.included(base)
        base.extend(ClassMethods)
      end
      module ClassMethods
        def parse(schema, data)
          data.each_with_object({}) do |(k, v), m|
            m[k] = schema.schema(v)
          end
        end
      end

      def check_properties(obj, path)
        valid = true
        keys = obj.keys
        value_or('properties', {}).each do |k, v|
          if keys.delete(k)
            valid &= v.validate(obj[k], path + [k])
          end
        end
        value_or('patternProperties', {}).each do |k, v|
          regex = Regexp.new(k) # TODO make regexp on schema parsing
          keys.dup.each do |key|
            if regex.match key
              keys.delete key
              valid &= v.validate(obj[key], path + [key])
            end
          end
        end
        if (additional = value_or('additionalProperties', true)) == false && keys.size > 0
          error path
          false
        else
          if additional.is_a?(Schema)
            keys.each do |k|
              valid &= additional.validate(obj[k], path + [k])
            end
          end
          valid
        end
      end
    end

    class Properties < Validator
      include CheckProperties
      def validate(obj, path)
        check_properties obj, path
      end
    end

    class PatternProperties < Validator
      include CheckProperties
      def validate(obj, path)
        if schema.tree['properties']
          true
        else
          check_properties obj, path
        end
      end
    end

    module StubValidator
      def validate(obj, path)
        true
      end
    end

    class AdditionalProperties < Validator
      def self.parse(schema, data)
        if data.is_a? Hash
          schema.schema(data)
        else
          data
        end
      end
      include StubValidator
    end

    class MaxProperties < Validator
      extend PureValue
      include SimpleBoolCheck

      def bool_check(obj)
        obj.size <= value
      end
    end

    class MinProperties < Validator
      extend PureValue
      include SimpleBoolCheck

      def bool_check(obj)
        obj.size >= value
      end
    end

    class Pattern < Validator
      def self.parse(schema, data)
        Regexp.new(data)
      end

      def validate(obj, path)
        !!value.match(obj)
      end
    end

    class Items < Validator
      def self.parse(schema, data)
        if data.is_a?(Array)
          data.map { |v| schema.schema(v) }
        else
          schema.schema(data)
        end
      end

      def validate(obj, path)
        valid = true
        if value.is_a?(Array)
          additional_items = value_or('additionalItems', true)
          if obj.size > value.size && additional_items == false
            valid = false
          else
            obj.each_with_index do |v, i|
              schema = value[i] || (additional_items.is_a?(Schema) && additional_items)
              if schema
                valid &= schema.validate(v, path + [i])
              else
                break
              end
            end
          end
        else
          obj.each_with_index do |v, i|
            valid &= value.validate(v, path + [i])
          end
        end
        valid
      end
    end

    class AdditionalItems < Validator
      def self.parse(schema, data)
        if data.is_a? Hash
          schema.schema(data)
        else
          data
        end
      end
      include StubValidator
    end

    class MaxItems < Validator
      extend PureValue
      include SimpleBoolCheck

      def bool_check(obj)
        obj.size <= value
      end
    end

    class MinItems < Validator
      extend PureValue
      include SimpleBoolCheck

      def bool_check(obj)
        obj.size >= value
      end
    end

    class UniqueItems < Validator
      extend PureValue
      include SimpleBoolCheck
      def bool_check(obj)
        return true if value == false
        obj.uniq.size == obj.size
      end
    end
  end


  VALIDATORS = {
    :common => {
      'type' => Validators::Type,
      'enum' => Validators::Enum,
      'not' => Validators::Not,
      'oneOf' => Validators::OneOf,
      'anyOf' => Validators::AnyOf,
      'allOf' => Validators::AllOf
    },
    Numeric => {
      'multipleOf' => Validators::MultipleOf,
      'minimum' => Validators::Minimum,
      'maximum' => Validators::Maximum
    },
    Hash => {
      'properties' => Validators::Properties,
      'patternProperties' => Validators::PatternProperties,
      'additionalProperties' => Validators::AdditionalProperties,
      'maxProperties' => Validators::MaxProperties,
      'minProperties' => Validators::MinProperties,
      'required' => Validators::Required,
      'dependencies' => Validators::Dependencies
    },
    String => {
      'minLength' => Validators::MinLength,
      'maxLength' => Validators::MaxLength,
      'pattern' => Validators::Pattern
    },
    Array => {
      'items' => Validators::Items,
      'additionalItems' => Validators::AdditionalItems,
      'maxItems' => Validators::MaxItems,
      'minItems' => Validators::MinItems,
      'uniqueItems' => Validators::UniqueItems
    }
  }

  FLAT_VALIDATORS = VALIDATORS.reduce({}) { |m, (k, v)| v.each { |name, validator| m[name] = validator }; m }

  class Schema
    module ParseData
      def common(obj)
        validators(:enum, :type, :all_of, :any_of, :one_of).each do
        end
      end
      def object(obj)
      end

      def string(str)

      end

      def integer(int)

      end

      def array(arr)

      end
    end

    def self.parse(data)
      Schemantic::Context.parse(data)
    end

    attr_reader :context, :tree, :parent, :id
    def initialize(context, parent = nil)
      @parent = parent
      @context = context
      @tree = {}
    end

    def make_id(id)
      if id && parent
        parent.id.merge id
      elsif id
        context.internal_uri.merge(id)
      else
        context.internal_uri.merge('#')
      end
    end

    def set_id(id = nil)
      @id = make_id id
      context.set_mapping @id, self
    end

    def parse(data)
      set_id data['id']
      data.each do |k, v|
        validator = FLAT_VALIDATORS[k]
        tree[k] = if validator
                    validator.new_and_parse(self, v)
                  elsif v.is_a?(Hash)
                    schema(v)
                  else
                    v
                  end
      end
      self
    end

    def schema(data)
      context.parse(data, self)
    end

    def valid?(data)
      context.validate self, data
    end

    def on_external_ref(&clb)
      context.on_external_ref(&clb)
    end

    def errors
      context.errors
    end

    def validators_for_data(data)
      data_type = case data
                  when Numeric
                    Numeric
                  when String
                    String
                  when Hash
                    Hash
                  when Array
                    Array
                  else
                    nil
                  end
      validator_keys = VALIDATORS[:common].keys
      if data_type
        validator_keys += VALIDATORS[data_type].keys
      end
      (tree.keys & validator_keys).map { |k| tree[k] }
    end

    def validate(data, path = [])
      validators_for_data(data).all? do |validator|
        validator.validate(data, path)
      end
    end
  end

  # ref schema doesn't set_id, so you cannot reference to reference. it's valid?
  class RefSchema < Schema
    def initialize(context, parent, ref)
      super(context, parent)
      @ref = ref
    end

    def id
      @id ||= begin
                make_id @ref
              end
    end

    def tree
      @ref_tree ||= begin
                      schema = context.resolve_ref(id)
                      raise "can't resolve ref for #{id}" unless schema
                      schema.tree
                    end
    end
  end
end
