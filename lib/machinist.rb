require 'active_support'

module Machinist
  def self.included(base)
    base.extend(ClassMethods)
    base.cattr_accessor :nerfed
  end
    
  module ClassMethods
    def blueprint(&blueprint)
      @blueprint = blueprint
    end
  
    def make(attributes = {})
      raise "No blueprint for class #{self}" if @blueprint.nil?
      lathe = Lathe.new(self.new, attributes)
      lathe.instance_eval(&@blueprint)
      if nerfed
        lathe.object
      else
        lathe.object.save!
        returning(lathe.object.reload) do |object|
          yield object if block_given?
        end
      end
    end
    
    def make_unsaved(attributes = {})
      with_save_nerfed { make(attributes) }
    end
    
    def with_save_nerfed
      begin
        self.nerfed = true
        yield
      ensure
        self.nerfed = false
      end
    end
  end
  
  class Lathe
    def initialize(object, attributes)
      @object = object
      @assigned_attributes = []
      attributes.each do |key, value|
        @object.send("#{key}=", value)
        @assigned_attributes << key
      end
    end

    attr_reader :object

    def method_missing(symbol, *args, &block)
      if @assigned_attributes.include?(symbol)
        @object.send(symbol)
      else
        value = if block
          block.call
        elsif args.first.is_a?(Hash) || args.empty?
          symbol.to_s.camelize.constantize.make(args.first || {})
        else
          args.first
        end
        @object.send("#{symbol}=", value)
        @assigned_attributes << symbol
      end
    end
  end
end
