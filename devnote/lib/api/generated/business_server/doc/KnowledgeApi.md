# devnote_business_api.api.KnowledgeApi

## Load the API package
```dart
import 'package:devnote_business_api/api.dart';
```

All URIs are relative to *http://localhost:8081*

Method | HTTP request | Description
------------- | ------------- | -------------
[**computeCoverage**](KnowledgeApi.md#computecoverage) | **GET** /api/v1/knowledge/graph/coverage | Compute graph coverage statistics
[**computeGraphEdges**](KnowledgeApi.md#computegraphedges) | **GET** /api/v1/knowledge/graph/edges | Compute all graph edges
[**computeGraphMetrics**](KnowledgeApi.md#computegraphmetrics) | **GET** /api/v1/knowledge/graph/metrics | Compute knowledge graph metrics
[**createKnowledgeRelation**](KnowledgeApi.md#createknowledgerelation) | **POST** /api/v1/knowledge/relations | Create a knowledge relation between two notes
[**deleteKnowledgeRelation**](KnowledgeApi.md#deleteknowledgerelation) | **DELETE** /api/v1/knowledge/relations/{id} | Delete a knowledge relation
[**findOrphanNotes**](KnowledgeApi.md#findorphannotes) | **GET** /api/v1/knowledge/graph/orphans | Find orphan notes (no relations)
[**findShortestPath**](KnowledgeApi.md#findshortestpath) | **GET** /api/v1/knowledge/path | Find shortest path between two notes
[**getKnowledgeRelations**](KnowledgeApi.md#getknowledgerelations) | **GET** /api/v1/knowledge/notes/{noteId}/relations | Get all knowledge relations for a note
[**suggestRelatedNotes**](KnowledgeApi.md#suggestrelatednotes) | **GET** /api/v1/knowledge/suggest/{noteId} | Suggest related notes


# **computeCoverage**
> SuccessResponse computeCoverage()

Compute graph coverage statistics

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();

try {
    final result = api_instance.computeCoverage();
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->computeCoverage: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **computeGraphEdges**
> SuccessResponse computeGraphEdges()

Compute all graph edges

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();

try {
    final result = api_instance.computeGraphEdges();
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->computeGraphEdges: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **computeGraphMetrics**
> ComputeGraphMetrics200Response computeGraphMetrics()

Compute knowledge graph metrics

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();

try {
    final result = api_instance.computeGraphMetrics();
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->computeGraphMetrics: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ComputeGraphMetrics200Response**](ComputeGraphMetrics200Response.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createKnowledgeRelation**
> SuccessResponse createKnowledgeRelation(createKnowledgeRelationRequest)

Create a knowledge relation between two notes

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();
final createKnowledgeRelationRequest = CreateKnowledgeRelationRequest(); // CreateKnowledgeRelationRequest | 

try {
    final result = api_instance.createKnowledgeRelation(createKnowledgeRelationRequest);
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->createKnowledgeRelation: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createKnowledgeRelationRequest** | [**CreateKnowledgeRelationRequest**](CreateKnowledgeRelationRequest.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteKnowledgeRelation**
> SuccessResponse deleteKnowledgeRelation(id)

Delete a knowledge relation

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.deleteKnowledgeRelation(id);
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->deleteKnowledgeRelation: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **findOrphanNotes**
> SuccessResponse findOrphanNotes()

Find orphan notes (no relations)

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();

try {
    final result = api_instance.findOrphanNotes();
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->findOrphanNotes: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **findShortestPath**
> ShortestPathResponse findShortestPath(from, to)

Find shortest path between two notes

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();
final from = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Source note ID
final to = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Target note ID

try {
    final result = api_instance.findShortestPath(from, to);
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->findShortestPath: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **from** | **String**| Source note ID | 
 **to** | **String**| Target note ID | 

### Return type

[**ShortestPathResponse**](ShortestPathResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getKnowledgeRelations**
> SuccessResponse getKnowledgeRelations(noteId)

Get all knowledge relations for a note

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();
final noteId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getKnowledgeRelations(noteId);
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->getKnowledgeRelations: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **noteId** | **String**|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **suggestRelatedNotes**
> SuccessResponse suggestRelatedNotes(noteId, limit)

Suggest related notes

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = KnowledgeApi();
final noteId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final limit = 56; // int | 

try {
    final result = api_instance.suggestRelatedNotes(noteId, limit);
    print(result);
} catch (e) {
    print('Exception when calling KnowledgeApi->suggestRelatedNotes: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **noteId** | **String**|  | 
 **limit** | **int**|  | [optional] [default to 10]

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

