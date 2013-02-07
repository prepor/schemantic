require 'uri'
require 'schemantic'
require 'schemantic/validators'
module Schemantic
  class Schema
    class Error < Schemantic::Error; end
    class ParseError < Error; end
    class Context
      attr_reader :errors
      def self.parse(data, options = {})
        new(options).parse(data)
      end

      def self.validate(schema, data)
        schema.context.validate(schema, data)
      end

      attr_reader :internal_uri, :options
      def initialize(options = {})
        @errors = []
        @mapping = {}
        @options = options
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

    def self.parse(data, options = {})
      Context.parse(data, options)
    end

    attr_reader :context, :tree, :parent, :id
    def initialize(context, parent = nil)
      @parent = parent
      @context = context
      @tree = {}
    end

    def id
      @id || (parent && parent.id)
    end

    def make_id(id)
      if id && parent
        parent.id.merge id
      elsif id
        context.internal_uri.merge(id)
      elsif parent.nil?
        context.internal_uri.merge('#')
      end
    end

    def set_id(id = nil)
      @id = make_id id
      context.set_mapping @id, self if @id
    end

    def parse(data, options = {})
      validate_schema_itself(data) unless context.options[:dont_validate]
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

    def schema(data, parent = nil)
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

    def validate_schema_itself(data)
      unless SCHEMA_ITSELF.validate(data)
        raise ParseError.new
      end
    end

    SCHEMA_ITSELF = Schema.parse MultiJson.load(File.read(Schemantic::SCHEMA_ITSELF_FILE)), dont_validate: true
  end
end
