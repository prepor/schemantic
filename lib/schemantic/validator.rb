module Schemantic
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
end
