require 'spec_helper'

describe Schemantic do
  describe Schemantic::Schema do
    def valid?(data = {})
      valid_schema?(schema, data)
    end

    def valid_schema?(schema, data)
      validate(schema, data).must_equal true
    end

    def invalid?(data = {}, errors = nil)
      invalid_schema? schema, data, errors
    end

    def invalid_schema?(schema, data, errors = nil)
      validate(schema, data).must_equal false
      if errors
        schema.errors.must_equal errors
      end
    end

    def validate(schema, data)
      schema.valid?(data)
    end
    let(:schema) { Schemantic::Schema.parse(schema_data) }
    describe "simple schema" do
      let(:schema_data) do
        {
          'type' => 'object',
          'properties' => {
            'a' => { 'type' => 'integer' },
            'b' => { 'type' => 'string' },
            'c' => { 'type' => 'integer' }
          },
          'required' => ['a', 'b']
        }
      end

      describe "valid data with 2 property" do
        let(:data) { { 'a' => 1, 'b' => 'foo' } }
        it "should be valid" do
          valid? data
        end
      end

      describe "valid data with 3 property" do
        let(:data) { {'a' => 1, 'b' => 'foo', 'c' => 2 } }
        it "should be valid" do
          valid? data
        end
      end

      describe "invalid data with 1 property" do
        let(:data) { {'a' => 1 } }
        it "should be invalid" do
          invalid? data, [{ path: [], validator: Schemantic::Validators::Required, params: ['a', 'b'] }]
        end
      end

      describe "invalid data with 3 properties" do
        let(:data) { {'a' => 1, 'b' => 'foo', 'c' => 'bar' } }
        it "should be invalid" do
          invalid? data, [{ path: ['c'], validator: Schemantic::Validators::Type, params: 'integer' }]
        end
      end

      describe "invalid data with 3 properties #2" do
        let(:data) { {'a' => 1, 'b' => 1, 'c' => 'bar' } }
        it "should be invalid" do
          invalid? data, [
            { path: ['b'], validator: Schemantic::Validators::Type, params: 'string' },
            { path: ['c'], validator: Schemantic::Validators::Type, params: 'integer' }
            ]
        end
      end
    end

    describe "validators" do
      describe "required" do
        let(:schema_data) do
          {
            'type' => 'object',
            'required' => ['a', 'b']
          }
        end
        it "should be valid" do
          valid? 'a' => 'foo', 'b' => 'bar'
        end

        it "should be invalid" do
          errors = [{ path: [], validator: Schemantic::Validators::Required, params: ['a', 'b'] }]
          invalid?({ 'a' => 'foo' }, errors)
          invalid?({ 'b' => 'foo', 'c' => 'bar' }, errors)
        end
      end

      describe "type" do
        def schema_for_type(type)
          Schemantic::Schema.parse('type' => type)
        end

        def errors_for_type(type)
          [{ path: [], validator: Schemantic::Validators::Type, params: type }]
        end

        it "should be valid" do
          valid_schema? schema_for_type('integer'), 1
          valid_schema? schema_for_type('string'), 'foo'
          valid_schema? schema_for_type('boolean'), false
          valid_schema? schema_for_type('array'), [1,2]
          valid_schema? schema_for_type('object'), 'foo' => 'bar'
          valid_schema? schema_for_type('null'), nil
        end

        it "should be invalid" do
          invalid_schema? schema_for_type('integer'), "100", errors_for_type('integer')
          invalid_schema? schema_for_type('string'), ['foo'], errors_for_type('string')
          invalid_schema? schema_for_type('boolean'), 'yes', errors_for_type('boolean')
          invalid_schema? schema_for_type('array'), { 'foo' => 'bar' }, errors_for_type('array')
          invalid_schema? schema_for_type('object'), ['foo', 'bar'], errors_for_type('object')
          invalid_schema? schema_for_type('null'), "null", errors_for_type('null')
        end
      end

      describe "properties" do
        describe "with additional properties" do
          let(:schema_data) do
            {
              'properties' => {
                'a' => { 'type' => 'integer' }
              },
              'additionalProperties' => { 'type' => 'string' }
            }
          end

          it "should be valid" do
            valid?
            valid? 'a' => 1
            valid? 'a' => 1, 'b' => 'foo'
            valid? 'b' => 'foo'
          end

          it "should be invalid" do
            invalid? 'a' => 'foo'
            invalid? 'a' => 'foo', 'b' => 'bar'
            invalid? 'b' => 1
            invalid? 'a' => 1, 'b' => 2
          end
        end

        describe "without additional properties" do
          let(:schema_data) do
            {
              'properties' => {
                'a' => { 'type' => 'integer' }
              },
              'additionalProperties' => false
            }
          end

          it "should be valid" do
            valid?
            valid? 'a' => 1
          end

          it "should be invalid" do
            invalid? 'a' => 1, 'b' => 'foo'
            invalid? 'b' => 'foo'
            invalid? 'a' => 'foo'
            invalid? 'a' => 'foo', 'b' => 'bar'
          end
        end

        describe "patternProperties" do
          let(:schema_data) do
            {
              'patternProperties' => {
                '_id$' => { 'type' => 'integer' }
              }
            }
          end

          it "should be valid" do
            valid?
            valid? 'text' => 'foo'
            valid? 'user_id_link' => 'foo', 'user_id' => 2
          end

          it "should be invalid" do
            invalid? 'user_id' => 'foo'
          end
        end

        describe "mix" do
          let(:schema_data) do
            {
              'properties' => {
                'title' => { 'type' => 'string' }
              },
              'patternProperties' => {
                '_id$' => { 'type' => 'integer' }
              },
              'required' => ['title'],
              'additionalProperties' => false
            }
          end

          it "should be valid" do
            valid? 'title' => 'Hello'
            valid? 'title' => 'Hello', 'author_id' => 100, 'post_id' => 10
          end

          it "should be invalid" do
            invalid?
            invalid? 'title' => 1
            invalid? 'title' => 1, 'author_id' => 100
            invalid? 'title' => 'Hello', 'author_id' => 100, 'meta' => {}
            invalid? 'title' => 'Hello', 'author_id' => 'steve'
          end
        end
      end

      describe "oneOf" do
        let(:validator_params) do
          [
            {
              'type' => 'object',
              'properties' => {
                'a' => { 'type' => 'string' }
              }
            },
            {
              'type' => 'object',
              'properties' => {
                'b' => { 'type' => 'integer' }
              }
            }
          ]
        end
        let(:schema_data) do
          {
            'oneOf' => validator_params
          }
        end
        it "should be valid" do
          valid? 'a' => 'foo', 'b' => 'bar'
          valid? 'a' => 1, 'b' => 2
        end

        it "should be invalid" do
          errors = [{ path: [], validator: Schemantic::Validators::OneOf, params: schema.tree['oneOf'].value }]
          invalid?({ 'a' => 'foo', 'b' => 2 }, errors)
          invalid?({}, errors)
          invalid?("foo", errors)
        end
      end

      describe "items" do
        describe "as object" do
          let(:schema_data) do
            {
              'items' => { 'type' => 'integer' }
            }
          end

          it "should be valid" do
            valid?
            valid? []
            valid? [1, 2 ,3]
          end

          it "should be invalid" do
            invalid? ['foo'], [{ path: [0], validator: Schemantic::Validators::Type, params: 'integer' }]
            invalid? [1, 'foo', 'bar', 4], [
              { path: [1], validator: Schemantic::Validators::Type, params: 'integer' },
              { path: [2], validator: Schemantic::Validators::Type, params: 'integer' }
            ]
          end
        end

        describe "as array" do
          let(:items) do
            {
              'items' => [{ 'type' => 'integer' }, { 'type' => 'string' }]
            }
          end

          let(:schema_data) do
            items
          end

          it "should be valid" do
            valid? []
            valid? [1]
            valid? [1, 'foo']
            valid? [1, 'foo', 2, 'bar']
          end

          it "should be invalid" do
            invalid? ['foo']
            invalid? [1, 2]
          end

          describe "with additional items as false" do
            let(:schema_data) do
              items.merge 'additionalItems' => false
            end

            it "should be valid" do
              valid? []
              valid? [1]
              valid? [1, 'foo']
            end

            it "should be invalid" do
              invalid? ['foo']
              invalid? [1, 2]
              invalid? [1, 'foo', 2, 'bar']
            end
          end
          describe "with additional items as object" do
            let(:schema_data) do
              items.merge 'additionalItems' => { 'type' => 'string' }
            end

            it "should be valid" do
              valid? []
              valid? [1]
              valid? [1, 'foo']
              valid? [1, 'foo', 'bar', 'zoo']
            end

            it "should be invalid" do
              invalid? ['foo']
              invalid? [1, 2]
              invalid? [1, 'foo', 2, 'bar']
            end

          end
        end
      end

      describe "minItems" do
        let(:schema_data) do
          {
            'minItems' => 1
          }
        end

        it "should be valid" do
          valid?
          valid? [1]
          valid? [1, 2]
        end

        it "should be invalid" do
          invalid? []
        end
      end

      describe "maxItems" do
        let(:schema_data) do
          {
            'maxItems' => 3
          }
        end

        it "should be valid" do
          valid?
          valid? []
          valid? [1, 2, 3]
        end

        it "should be invalid?" do
          invalid? [1, 2, 3, 4]
        end
      end

      describe "anyOf" do
        let(:schema_data) do
          {
            'anyOf' => [
              {
                'type' => 'object',
                'properties' => {
                  'a' => { 'type' => 'string' }
                }
              },
              {
                'type' => 'object',
                'properties' => {
                  'b' => { 'type' => 'integer' }
                }
              }
            ]
          }
        end
        it "should be valid" do
          valid? 'a' => 'foo', 'b' => 'bar'
          valid? 'a' => 1, 'b' => 2
          valid?
          valid? 'a' => 'foo', 'b' => 2
        end

        it "should be invalid" do
          errors = [{ path: [], validator: Schemantic::Validators::AnyOf, params: schema.tree['anyOf'].value }]
          invalid? "foo", errors
        end
      end

      describe "uniqueItems" do
        let(:schema_data) do
          {
            'uniqueItems' => true
          }
        end

        it "should be valid" do
          valid?
          valid? [1, 2]
          valid? []
          valid? [1, 'foo']
        end

        it "should be invalid" do
          invalid? [1, 1]
          invalid? [1, 2, 1]
          invalid? [1, 'foo', 'foo']
        end
      end

      describe "minLength" do
        let(:schema_data) do
          {
            'minLength' => 3
          }
        end

        it "should be valid" do
          valid?
          valid? "foo"
          valid? "hello"
        end

        it "should be invalid" do
          invalid? ""
          invalid? "hi"
        end
      end

      describe "maxLength" do
        let(:schema_data) do
          {
            'maxLength' => 3
          }
        end

        it "should be valid" do
          valid?
          valid? "foo"
          valid? "fo"
        end

        it "should be invalid" do
          invalid? "hello"
        end
      end

      describe "pattern" do
        let(:schema_data) do
          {
            'pattern' => '^\d'
          }
        end

        it "should be valid" do
          valid?
          valid? '0foo'
          valid? '00bar'
        end

        it "should be invalid" do
          invalid? ""
          invalid? "bar"
        end
      end

      describe "minimum" do
        let(:schema_data) do
          {
            'minimum' => 3
          }
        end

        it "should be valid" do
          valid? 3
          valid? 4
        end

        it "should be invalid" do
          invalid? 0
          invalid? 1
        end

        describe "exclusiveMinimum" do
          let(:schema_data) do
            {
              'minimum' => 3,
              'exclusiveMinimum' => true
            }
          end

          it "should be valid" do
            valid? 4
          end

          it "should be invalid" do
            invalid? 0
            invalid? 1
            invalid? 3
          end
        end
      end

      describe "maximum" do
        let(:schema_data) do
          {
            'maximum' => 3
          }
        end

        it "should be valid" do
          valid? 0
          valid? 1
          valid? 3
        end

        it "should be invalid" do
          invalid? 4
        end

        describe "exclusiveMaximum" do
          let(:schema_data) do
            {
              'maximum' => 3,
              'exclusiveMaximum' => true
            }
          end

          it "should be valid" do
            valid? 0
            valid? 1
          end

          it "should be invalid" do
            invalid? 3
            invalid? 4
          end
        end
      end


      describe "allOf" do
        let(:schema_data) do
          {
            'allOf' => [
              {
                'type' => 'object',
                'properties' => { 'a' => { 'type' => 'string' } }
              },
              {
                'type' => 'object',
                'properties' => { 'b' => { 'type' => 'integer' } }
              }
            ]
          }
        end

        it "should be valid" do
          valid?
          valid? 'a' => "foo"
          valid? 'b' => 1
          valid? 'a' => 'foo', 'b' => 1
        end

        it "should be invalid" do
          errors = [{ path: [], validator: Schemantic::Validators::AllOf, params: schema.tree['allOf'].value }]
          invalid?({ 'b' => 'foo' }, errors)
          invalid?({ 'a' => 1, 'b' => 'foo' }, errors)
          invalid?({ 'a' => 1, 'b' => 2 }, errors)
        end
      end

      describe "dependencies" do
        describe "schema dependencies" do
          let(:schema_data) do
            {
              'dependencies' => {
                'a' => { 'properties' => { 'b' => { 'type' => 'string' } } },
                'c' => { 'properties' => { 'b' => { 'type' => 'integer' } } }
              }
            }
          end

          it "should be valid" do
            valid? 'b' => nil
            valid? 'a' => 'ok', 'b' => 'foo'
            valid? 'c' => 'ok', 'b' => 123
          end

          it "should be invalid" do
            invalid? 'a' => 'ok', 'b' => nil
            invalid? 'a' => 'ok', 'b' => 123
            invalid? 'c' => 'ok', 'b' => 'foo'
          end
        end

        describe "properties dependencies" do
          let(:validator_params) do
            {
              'a' => ['b', 'c'],
              'c' => ['b']
            }
          end
          let(:schema_data) do
            {
              'dependencies' => validator_params
            }
          end
          it "should be valid" do
            valid?
            valid? 'b' => nil, 'c' => nil
            valid? 'a' => nil, 'b' => nil, 'c' => nil
          end

          it "should be invalid" do
            errors = [{ path: [], validator: Schemantic::Validators::Dependencies, params: schema.tree['dependencies'].value }]
            invalid?({ 'a' => nil }, errors)
            invalid?({ 'a' => nil, 'b' => nil }, errors)
            invalid?({ 'c' => nil }, errors)
          end
        end

        describe "mix" do
          let(:schema_data) do
            {
              'dependencies' => {
                'a' => ['b', 'c'],
                'b' => { 'properties' => { 'a' => { 'type' => 'boolean' } } }
              }
            }
          end

          it "should be valid" do
            valid?
            valid? 'a' => true, 'b' => 1, 'c' => 2
          end

          it "should be invalid" do
            invalid? 'a' => 1, 'b' => 1, 'c' => 2
            invalid? 'a' => true
            invalid? 'a' => 1, 'b' => 1
          end
        end
      end

      describe "enum" do
        let(:schema_data) do
          {
            'enum' => [1, 'foo']
          }
        end

        it "should be valid" do
          valid? 1
          valid? 'foo'
        end

        it "should be invalid" do
          invalid? 2
          invalid?
          invalid? 'bar'
        end
      end

      describe "not" do
        let(:schema_data) do
          {
            'not' => { 'type' => 'string' }
          }
        end

        it "should be valid" do
          valid? 1
          valid? true
          valid?
        end

        it "should be invalid" do
          invalid? 'foo'
        end
      end

      describe "multipleOf" do
        let(:schema_data) do
          {
            'multipleOf' => 4
          }
        end

        it "should be valid" do
          valid? 4
          valid? 16
          valid? 'foo'
        end

        it "should be invalid" do
          invalid? 2
          invalid? 7
        end
      end

      describe "apply validators by type" do
        let(:schema_data) do
          {
            'maxLength' => 4,
            'maximum' => 10
          }
        end
        it "should be valid" do
          valid? 10
          valid? "1000"
        end

        it "should be invalid" do
          invalid? 11, [{ path: [], validator: Schemantic::Validators::Maximum, params: 10 }]
          invalid? "10000", [{ path: [], validator: Schemantic::Validators::MaxLength, params: 4 }]
        end
      end
    end

    describe "scopes" do
      let(:schema_data) do
        {
          'definitions' => {
            'int' => {
              'type' => 'integer'
            },
            'str' => {
              'id' => '#str',
              'type' => 'string'
            }
          },
          'properties' => {
            'a' => { '$ref' => '#/definitions/int' },
            'b' => { '$ref' => '#str' }
          }
        }
      end

      it "should be valid" do
        valid?
        valid? 'a' => 1, 'b' => 'foo'
      end

      it "should be invalid" do
        invalid? 'a' => 'foo'
        invalid? 'b' => 123
      end

      describe "recursive" do
        let(:schema_data) do
          {
            'oneOf' => [
              {
                'type' => 'object',
                'properties' => {
                  'left' => { '$ref' => '#' },
                  'right' => { '$ref' => '#' }
                },
                'required' => ['left', 'right']
              },
              { 'type' => 'integer' },
              { 'type' => 'null' }
            ]
          }
        end

        it "should be valid" do
          valid? 'left' => 1, 'right' => { 'left' => 3, 'right' => { 'left' => nil, 'right' => 5 } }
        end

        it "should be invalid" do
          invalid? 'left' => 1, 'right' => { 'left' => 'hello', 'right' => nil }
          invalid? 'left' => 1, 'right' => "foo"
        end
      end

      describe "external schemas" do
        let(:schema_data) do
          {
            'inner' => {
              'id' => 'inner.json',
              'type' => 'string'
            },
            'properties' => {
              'a' => { '$ref' => 'inner.json' },
              'b' => { '$ref' => 'outer.json' }
            }
          }
        end

        it "should be valid" do
          schema.on_external_ref do |ref|
            { 'type' => 'integer' }
          end
          valid? 'a' => 'foo', 'b' => 123
        end

        it "should be invalid" do
          schema.on_external_ref do |ref|
            { 'type' => 'integer' }
          end
          invalid? 'a' => 1, 'b' => 'foo'
          invalid? 'a' => 'foo', 'b' => 'bar'
        end

        describe "many refs to external schema" do
          let(:schema_data) do
            {
              'properties' => {
                'a' => { '$ref' => 'outer.json#foo' },
                'b' => { '$ref' => 'outer.json#/definitions/bar' }
              }
            }
          end
          it "should cache external refs" do
            i = 0
            schema.on_external_ref do |ref|
              i += 1
              {
                'foo' => { 'id' => '#foo', 'type' => 'string' },
                'definitions' => {
                  'bar' => { 'type' => 'integer' }
                }
              }
            end
            valid? 'a' => 'foo', 'b' => 123
            invalid? 'a' => 1, 'b' => 123
            invalid? 'a' => 'foo', 'b' => 'bar'
            i.must_equal 1
          end
        end

      end
    end
  end
end
