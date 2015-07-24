module JSONAPI
  class Operation
    attr_reader :resource_klass, :options, :transactional

    def initialize(request)
      @context = request.context
      @resource_klass = request.resource_klass
      @transactional = true
    end

    def apply
    end
  end

  class FindOperation < Operation
    attr_reader :filters, :include_directives, :sort_criteria, :paginator

    def initialize(request)
      @filters = request.filters
      @include_directives = request.include_directives
      @sort_criteria = request.sort_criteria || []
      @paginator = request.paginator
      @transactional = false
      super(request)
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

  class ShowOperation < Operation
    attr_reader :id, :include_directives

    def initialize(request)
      @id = request.params[:id]
      @include_directives = request.include_directives
      @transactional = false
      super(request)
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

  class ShowRelationshipOperation < Operation
    attr_reader :parent_key, :relationship_type

    def initialize(request)
      parent_key = request.params.require(request.resource_klass._as_parent_key)
      @parent_key = request.resource_klass.verify_key(parent_key)
      @relationship_type = request.params[:relationship]
      @transactional = false
      super(request)
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

  class ShowRelatedResourceOperation < Operation
    attr_reader :source_klass, :source_id, :relationship_type

    def initialize(request)
      @source_klass = request.source_klass
      @source_id = request.source_id
      @relationship_type = request.params[:relationship]
      @transactional = false
      super(request)
    end

    def apply
      source_resource = @source_klass.find_by_key(@source_id, context: @context)

      related_resource = source_resource.public_send(@relationship_type)

      return JSONAPI::ResourceOperationResult.new(:ok, related_resource)

    rescue JSONAPI::Exceptions::Error => e
      return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
    end
  end

  class ShowRelatedResourcesOperation < Operation
    attr_reader :source_klass, :source_id, :relationship_type, :filters, :sort_criteria, :paginator

    def initialize(request)
      @source_klass = request.source_klass
      @source_id = request.source_id
      @relationship_type = request.params[:relationship]
      @filters = request.source_klass.verify_filters(request.filters, request.context)
      @sort_criteria = request.sort_criteria
      @paginator = request.paginator
      @transactional = false
      super(request)
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

  class CreateResourceOperation < Operation
    attr_reader :data

    def initialize(request, data)
      @data = data
      super(request)
    end

    def apply
      resource = @resource_klass.create(@context)
      result = resource.replace_fields(@data)

      return JSONAPI::ResourceOperationResult.new((result == :completed ? :created : :accepted), resource)

    rescue JSONAPI::Exceptions::Error => e
      return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
    end
  end

  class RemoveResourceOperation < Operation
    attr_reader :resource_id
    def initialize(request, resource_id)
      @resource_id = resource_id
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.remove

      return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)

    rescue JSONAPI::Exceptions::Error => e
      return JSONAPI::ErrorsOperationResult.new(e.errors[0].code, e.errors)
    end
  end

  class ReplaceFieldsOperation < Operation
    attr_reader :data, :resource_id

    def initialize(request, resource_id, data)
      @resource_id = resource_id
      @data = data
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.replace_fields(data)

      return JSONAPI::ResourceOperationResult.new(result == :completed ? :ok : :accepted, resource)
    end
  end

  class ReplaceToOneRelationshipOperation < Operation
    attr_reader :resource_id, :relationship_type, :key_value

    def initialize(request, key_value)
      @resource_id = request.params.require(request.resource_klass._as_parent_key)
      @key_value = key_value
      @relationship_type = request.params.require(:relationship).to_sym
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.replace_to_one_link(@relationship_type, @key_value)

      return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
    end
  end

  class ReplacePolymorphicToOneRelationshipOperation < Operation
    attr_reader :resource_id, :relationship_type, :key_value, :key_type

    def initialize(request, key_value, key_type)
      @resource_id = request.params.require(request.resource_klass._as_parent_key)
      @key_value = key_value
      @key_type = key_type
      @relationship_type = request.params.require(:relationship).to_sym
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.replace_polymorphic_to_one_link(@relationship_type, @key_value, @key_type)

      return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
    end
  end

  class CreateToManyRelationshipOperation < Operation
    attr_reader :resource_id, :relationship_type, :data

    def initialize(request, data)
      @resource_id = request.params.require(request.resource_klass._as_parent_key)
      @data = data
      @relationship_type = request.params.require(:relationship).to_sym
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.create_to_many_links(@relationship_type, @data)

      return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
    end
  end

  class ReplaceToManyRelationshipOperation < Operation
    attr_reader :resource_id, :relationship_type, :data

    def initialize(request, data)
      @resource_id = request.params.require(request.resource_klass._as_parent_key)
      @data = data
      @relationship_type = request.params.require(:relationship).to_sym
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.replace_to_many_links(@relationship_type, @data)

      return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
    end
  end

  class RemoveToManyRelationshipOperation < Operation
    attr_reader :resource_id, :relationship_type, :associated_key

    def initialize(request, associated_key)
      @resource_id = request.params.require(request.resource_klass._as_parent_key)
      @associated_key = associated_key
      @relationship_type = request.params.require(:relationship).to_sym
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.remove_to_many_link(@relationship_type, @associated_key)

      return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
    end
  end

  class RemoveToOneRelationshipOperation < Operation
    attr_reader :resource_id, :relationship_type

    def initialize(request)
      @resource_id = request.params.require(request.resource_klass._as_parent_key)
      @relationship_type = request.params.require(:relationship).to_sym
      super(request)
    end

    def apply
      resource = @resource_klass.find_by_key(@resource_id, context: @context)
      result = resource.remove_to_one_link(@relationship_type)

      return JSONAPI::OperationResult.new(result == :completed ? :no_content : :accepted)
    end
  end
end
