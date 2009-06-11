require 'sham'
 
module Machinist

  # A Lathe is used to execute the blueprint and construct an object.
  #
  # The blueprint is instance_eval'd against the Lathe.
  class Lathe
    def self.run(adapter, object, *args)
      blueprint       = object.class.blueprint
      named_blueprint = object.class.blueprint(args.shift) if args.first.is_a?(Symbol)
      attributes      = args.pop || {}

      blueprint_chain = [named_blueprint]
      klass = object.class
      while klass.respond_to? :blueprint
        blueprint_chain << klass.blueprint
        klass = klass.superclass
      end

      raise "No blueprint for class #{object.class}" if blueprint_chain.compact.empty?
      returning self.new(adapter, object, attributes) do |lathe|
        blueprint_chain.each do |blueprint|
          lathe.instance_eval(&blueprint) if blueprint
        end
      end
    end
    
    def initialize(adapter, object, attributes = {})
      @adapter = adapter
      @object  = object
      attributes.each {|key, value| assign_attribute(key, value) }
    end

    def object
      yield @object if block_given?
      @object
    end
    
    def method_missing(symbol, *args, &block)
      if attribute_assigned?(symbol)
        # If we've already assigned the attribute, return that.
        @object.send(symbol)
      elsif @adapter.has_association?(@object, symbol) && !@object.send(symbol).nil?
        # If the attribute is an association and is already assigned, return that.
        @object.send(symbol)
      else
        # Otherwise generate a value and assign it.
        assign_attribute(symbol, generate_attribute_value(symbol, *args, &block))
      end
    end

    def assigned_attributes
      @assigned_attributes ||= {}
    end
    
    # Undef a couple of methods that are common ActiveRecord attributes.
    # (Both of these are deprecated in Ruby 1.8 anyway.)
    undef_method :id   if respond_to?(:id)
    undef_method :type if respond_to?(:type)
    
  private
    
    def assign_attribute(key, value)
      assigned_attributes[key.to_sym] = value
      @object.send("#{key}=", value)
    end
  
    def attribute_assigned?(key)
      assigned_attributes.has_key?(key.to_sym)
    end
    
    def generate_attribute_value(attribute, *args)
      if block_given?
        # If we've got a block, use that to generate the value.
        yield
      elsif !args.empty?
        # If we've got a constant, just use that.
        args.first
      else
        # Otherwise, look for an association or a sham.
        if @adapter.has_association?(object, attribute)
          @adapter.class_for_association(object, attribute).make(args.first || {})
        else
          Sham.send(attribute)
        end
      end
    end
    
  end

  # This sets a flag that stops make from saving objects, so
  # that calls to make from within a blueprint don't create
  # anything inside make_unsaved.
  def self.with_save_nerfed
    begin
      @@nerfed = true
      yield
    ensure
      @@nerfed = false
    end
  end

  @@nerfed = false
  def self.nerfed?
    @@nerfed
  end

end
