require 'schemantic/validator'
module Schemantic
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
end
