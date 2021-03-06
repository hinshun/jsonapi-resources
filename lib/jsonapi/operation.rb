module JSONAPI
  class Operation
    attr_reader :resource_klass, :options, :transactional

    def initialize(resource_klass, options = {})
      @context = options[:context]
      @resource_klass = resource_klass
      @options = options
      @transactional = true
    end

    def apply
    end

    class << self
      def resource_operation_for(resource_klass, operation)
        resource_operation_name = "#{resource_klass.to_s.underscore}_#{operation}"
        resource_operation = Operation.operation_for(resource_operation_name)
        resource_operation || Operation.operation_for(operation)
      end

      def operation_for(operation)
        operation_class_name = "#{operation.to_s.camelize}Operation"
        operation_class_name.safe_constantize
      end
    end
  end
end

class FindOperation < JSONAPI::Operation
  attr_reader :filters, :include_directives, :sort_criteria, :paginator

  def initialize(resource_klass, options = {})
    @filters = options[:filters]
    @include_directives = options[:include_directives]
    @sort_criteria = options.fetch(:sort_criteria, [])
    @paginator = options[:paginator]
    @transactional = false
    super(resource_klass, options)
  end

  def record_count
    @_record_count ||= @resource_klass.find_count(@resource_klass.verify_filters(@filters, @context),
                                                  context: @context,
                                                  include_directives: @include_directives)
  end

  def pagination_params
    if @paginator && JSONAPI.configuration.top_level_links_include_pagination
      options = {}
      options[:record_count] = record_count if @paginator.class.requires_record_count
      return @paginator.links_page_params(options)
    else
      return {}
    end
  end

  def apply
    resource_records = @resource_klass.find(@resource_klass.verify_filters(@filters, @context),
                                            context: @context,
                                            include_directives: @include_directives,
                                            sort_criteria: @sort_criteria,
                                            paginator: @paginator)

    options = {}
    if JSONAPI.configuration.top_level_links_include_pagination
      options[:pagination_params] = pagination_params
    end

    if JSONAPI.configuration.top_level_meta_include_record_count
      options[:record_count] = record_count
    end

    return JSONAPI::ResourcesOperationResult.new(:ok,
                                                 resource_records,
                                                 options)

  rescue JSONAPI::Exceptions::Error => e
    return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
  end
end

class ShowOperation < JSONAPI::Operation
  attr_reader :id, :include_directives

  def initialize(resource_klass, options = {})
    @id = options.fetch(:id)
    @include_directives = options[:include_directives]
    @transactional = false
    super(resource_klass, options)
  end

  def apply
    key = @resource_klass.verify_key(@id, @context)

    resource_record = resource_klass.find_by_key(key,
                                                 context: @context,
                                                 include_directives: @include_directives)

    return JSONAPI::ResourceOperationResult.new(:ok, resource_record)

  rescue JSONAPI::Exceptions::Error => e
    return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
  end
end

class ShowRelationshipOperation < JSONAPI::Operation
  attr_reader :parent_key, :relationship_type

  def initialize(resource_klass, options = {})
    @parent_key = options.fetch(:parent_key)
    @relationship_type = options.fetch(:relationship_type)
    @transactional = false
    super(resource_klass, options)
  end

  def apply
    parent_resource = resource_klass.find_by_key(@parent_key, context: @context)

    return JSONAPI::LinksObjectOperationResult.new(:ok,
                                                   parent_resource,
                                                   resource_klass._relationship(@relationship_type))

  rescue JSONAPI::Exceptions::Error => e
    return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
  end
end

class ShowRelatedResourceOperation < JSONAPI::Operation
  attr_reader :source_klass, :source_id, :relationship_type

  def initialize(resource_klass, options = {})
    @source_klass = options.fetch(:source_klass)
    @source_id = options.fetch(:source_id)
    @relationship_type = options.fetch(:relationship_type)
    @transactional = false
    super(resource_klass, options)
  end

  def apply
    source_resource = @source_klass.find_by_key(@source_id, context: @context)

    related_resource = source_resource.public_send(@relationship_type)

    return JSONAPI::ResourceOperationResult.new(:ok, related_resource)

  rescue JSONAPI::Exceptions::Error => e
    return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
  end
end

class ShowRelatedResourcesOperation < JSONAPI::Operation
  attr_reader :source_klass, :source_id, :relationship_type, :filters, :sort_criteria, :paginator

  def initialize(resource_klass, options = {})
    @source_klass = options.fetch(:source_klass)
    @source_id = options.fetch(:source_id)
    @relationship_type = options.fetch(:relationship_type)
    @filters = options[:filters]
    @sort_criteria = options[:sort_criteria]
    @paginator = options[:paginator]
    @transactional = false
    super(resource_klass, options)
  end

  def apply
    source_resource = @source_klass.find_by_key(@source_id, context: @context)

    related_resource = source_resource.public_send(@relationship_type,
                                            filters:  @filters,
                                            sort_criteria: @sort_criteria,
                                            paginator: @paginator)

    return JSONAPI::ResourceOperationResult.new(:ok, related_resource)

  rescue JSONAPI::Exceptions::Error => e
    return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
  end
end

class CreateResourceOperation < JSONAPI::Operation
  attr_reader :data

  def initialize(resource_klass, options = {})
    @data = options.fetch(:data)
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.create(@context)
    result = resource.replace_fields(@data)

    return JSONAPI::ResourceOperationResult.new((result == :completed ? :created : :accepted), resource)

  rescue JSONAPI::Exceptions::Error => e
    return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
  end
end

class RemoveResourceOperation < JSONAPI::Operation
  attr_reader :resource_id
  def initialize(resource_klass, options = {})
    @resource_id = options.fetch(:resource_id)
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.remove

    return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)

  rescue JSONAPI::Exceptions::Error => e
    return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
  end
end

class ReplaceFieldsOperation < JSONAPI::Operation
  attr_reader :data, :resource_id

  def initialize(resource_klass, options = {})
    @resource_id = options.fetch(:resource_id)
    @data = options.fetch(:data)
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.replace_fields(data)

    return JSONAPI::ResourceOperationResult.new(result == :completed ? :ok : :accepted, resource)
  end
end

class ReplaceToOneRelationshipOperation < JSONAPI::Operation
  attr_reader :resource_id, :relationship_type, :key_value

  def initialize(resource_klass, options = {})
    @resource_id = options.fetch(:resource_id)
    @key_value = options.fetch(:key_value)
    @relationship_type = options.fetch(:relationship_type).to_sym
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.replace_to_one_link(@relationship_type, @key_value)

    return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
  end
end

class ReplacePolymorphicToOneRelationshipOperation < JSONAPI::Operation
  attr_reader :resource_id, :relationship_type, :key_value, :key_type

  def initialize(resource_klass, options = {})
    @resource_id = options.fetch(:resource_id)
    @key_value = options.fetch(:key_value)
    @key_type = options.fetch(:key_type)
    @relationship_type = options.fetch(:relationship_type).to_sym
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.replace_polymorphic_to_one_link(@relationship_type, @key_value, @key_type)

    return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
  end
end

class CreateToManyRelationshipOperation < JSONAPI::Operation
  attr_reader :resource_id, :relationship_type, :data

  def initialize(resource_klass, options)
    @resource_id = options.fetch(:resource_id)
    @data = options.fetch(:data)
    @relationship_type = options.fetch(:relationship_type).to_sym
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.create_to_many_links(@relationship_type, @data)

    return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
  end
end

class ReplaceToManyRelationshipOperation < JSONAPI::Operation
  attr_reader :resource_id, :relationship_type, :data

  def initialize(resource_klass, options)
    @resource_id = options.fetch(:resource_id)
    @data = options.fetch(:data)
    @relationship_type = options.fetch(:relationship_type).to_sym
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.replace_to_many_links(@relationship_type, @data)

    return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
  end
end

class RemoveToManyRelationshipOperation < JSONAPI::Operation
  attr_reader :resource_id, :relationship_type, :associated_key

  def initialize(resource_klass, options)
    @resource_id = options.fetch(:resource_id)
    @associated_key = options.fetch(:associated_key)
    @relationship_type = options.fetch(:relationship_type).to_sym
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.remove_to_many_link(@relationship_type, @associated_key)

    return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
  end
end

class RemoveToOneRelationshipOperation < JSONAPI::Operation
  attr_reader :resource_id, :relationship_type

  def initialize(resource_klass, options)
    @resource_id = options.fetch(:resource_id)
    @relationship_type = options.fetch(:relationship_type).to_sym
    super(resource_klass, options)
  end

  def apply
    resource = @resource_klass.find_by_key(@resource_id, context: @context)
    result = resource.remove_to_one_link(@relationship_type)

    return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
  end
end
