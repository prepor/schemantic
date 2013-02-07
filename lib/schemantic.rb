require 'uri'
require 'multi_json'
module Schemantic
  VERSION = "0.4.0"
  class Error < RuntimeError;  end

  SCHEMA_ITSELF_FILE = File.join(File.dirname(File.expand_path(__FILE__)), '../', 'schemas/draft4.json')

  
end
