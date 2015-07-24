require File.expand_path('../../../test_helper', __FILE__)
require 'jsonapi-resources'
require 'json'

class ResponseDocumentTest < ActionDispatch::IntegrationTest
  def setup
    JSONAPI.configuration.json_key_format = :dasherized_key
    JSONAPI.configuration.route_format = :dasherized_route
  end

  def create_response_document(operation_results, resource_klass)
    JSONAPI::ResponseDocument.new(
      operation_results,
      {
        primary_resource_klass: resource_klass
      }
    )
  end

  def test_response_document
    request = JSONAPI::Request.new
    request.resource_klass = PlanetResource
    operations = [
      JSONAPI::CreateResourceOperation.new(request, {attributes: {'name' => 'Earth 2.0'}}),
      JSONAPI::CreateResourceOperation.new(request, {attributes: {'name' => 'Vulcan'}})
    ]

    request.operations = operations

    op = BasicOperationsProcessor.new()
    operation_results = op.process(request)

    response_doc = create_response_document(operation_results, PlanetResource)

    assert_equal :created, response_doc.status
    contents = response_doc.contents
    assert contents.is_a?(Hash)
    assert contents[:data].is_a?(Array)
    assert_equal 2, contents[:data].size
  end

  def test_response_document_multiple_find
    request = JSONAPI::Request.new
    request.resource_klass = PostResource
    request.filters = { id: '1' }

    other_request = request.dup
    other_request.filters = { id: '2' }

    operations = [
      JSONAPI::FindOperation.new(request),
      JSONAPI::FindOperation.new(other_request)
    ]

    request.operations = operations

    op = ActiveRecordOperationsProcessor.new()
    operation_results = op.process(request)

    response_doc = create_response_document(operation_results, PostResource)

    assert_equal :ok, response_doc.status
    contents = response_doc.contents
    assert contents.is_a?(Hash)
    assert contents[:data].is_a?(Array)
    assert_equal 2, contents[:data].size
  end
end
