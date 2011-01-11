module Octopus::Model
  def self.extended(base)
    base.send(:include, InstanceMethods)
    base.class_eval do
      attr_accessor :current_shard
      before_save :reload_connection

      if !Octopus.rails3?
        def after_initialize
          set_current_shard()
        end
      else
        after_initialize :set_current_shard
      end

      class << self
        alias_method_chain :connection, :octopus
      end
    end
  end


  def clean_table_name
    self.reset_table_name() if self != ActiveRecord::Base && self.respond_to?(:reset_table_name)
  end

  def using(shard)
    return self if defined?(::Rails) && !Octopus.environments.include?(Rails.env.to_s)
    clean_table_name()
    self.connection_proxy.using_enabled = true

    return Octopus::ScopeProxy.new(shard, self)
  end

  def should_use_normal_connection?
    (defined?(Rails) && Octopus.config() && !Octopus.environments.include?(Rails.env.to_s)) || self.read_inheritable_attribute(:establish_connection)
  end

  def connection_proxy
    Thread.current[:connection_proxy] ||= Octopus::Proxy.new(Octopus.config())
  end

  def connection_with_octopus()
    return connection_without_octopus() if should_use_normal_connection?

    self.connection_proxy().current_model = self
    self.connection_proxy()
  end

  def replicated_model()
    write_inheritable_attribute(:replicated, true)
  end

  def sharded_model()
    write_inheritable_attribute(:sharded, true)
  end

  def octopus_establish_connection(spec = nil)
    write_inheritable_attribute(:establish_connection, true)
    establish_connection(spec)
  end

  module InstanceMethods

    def should_set_current_shard?
      self.respond_to?(:current_shard) && !self.current_shard.nil?
    end

    def reload_connection()
      self.class.connection_proxy.current_shard = self.current_shard() if should_set_current_shard?
    end

    def set_current_shard
      if new_record? || self.class.connection_proxy.block
        self.current_shard = self.class.connection_proxy.current_shard
      else
        self.current_shard = self.class.connection_proxy.last_current_shard
      end
    end

  end

end

ActiveRecord::Base.extend(Octopus::Model)