# devnote_business_api.api.TagsApi

## Load the API package
```dart
import 'package:devnote_business_api/api.dart';
```

All URIs are relative to *http://localhost:8081*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createTag**](TagsApi.md#createtag) | **POST** /api/v1/tags | Create a tag
[**deleteTag**](TagsApi.md#deletetag) | **DELETE** /api/v1/tags/{id} | Delete a tag
[**getNotesByTag**](TagsApi.md#getnotesbytag) | **GET** /api/v1/tags/{id}/notes | Get all notes associated with a tag
[**getTag**](TagsApi.md#gettag) | **GET** /api/v1/tags/{id} | Get a tag by ID
[**getTagChildren**](TagsApi.md#gettagchildren) | **GET** /api/v1/tags/{id}/children | Get direct children of a tag
[**getTagHierarchy**](TagsApi.md#gettaghierarchy) | **GET** /api/v1/tags/{id}/hierarchy | Get full tag hierarchy (ancestors and descendants)
[**getTagStats**](TagsApi.md#gettagstats) | **GET** /api/v1/tags/{id}/stats | Get tag statistics
[**getTagsByNote**](TagsApi.md#gettagsbynote) | **GET** /api/v1/tags/by-note/{noteId} | Get all tags associated with a note
[**getTopTags**](TagsApi.md#gettoptags) | **GET** /api/v1/tags/top | Get most frequently used tags
[**linkTagToNote**](TagsApi.md#linktagtonote) | **POST** /api/v1/tags/{id}/notes/{noteId} | Link a tag to a note
[**listTags**](TagsApi.md#listtags) | **GET** /api/v1/tags | List tags with pagination
[**mergeTags**](TagsApi.md#mergetags) | **POST** /api/v1/tags/merge | Merge two tags (source into target)
[**splitTag**](TagsApi.md#splittag) | **POST** /api/v1/tags/split | Split a tag, creating a new tag for selected notes
[**unlinkTagFromNote**](TagsApi.md#unlinktagfromnote) | **DELETE** /api/v1/tags/{id}/notes/{noteId} | Unlink a tag from a note
[**updateTag**](TagsApi.md#updatetag) | **PUT** /api/v1/tags/{id} | Update a tag


# **createTag**
> SuccessResponse createTag(tagMeta)

Create a tag

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final tagMeta = TagMeta(); // TagMeta | 

try {
    final result = api_instance.createTag(tagMeta);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->createTag: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **tagMeta** | [**TagMeta**](TagMeta.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteTag**
> SuccessResponse deleteTag(id)

Delete a tag

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.deleteTag(id);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->deleteTag: $e\n');
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

# **getNotesByTag**
> PaginatedNoteMetaResponse getNotesByTag(id, page, pageSize)

Get all notes associated with a tag

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final page = 56; // int | 
final pageSize = 56; // int | 

try {
    final result = api_instance.getNotesByTag(id, page, pageSize);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->getNotesByTag: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 
 **page** | **int**|  | [optional] [default to 1]
 **pageSize** | **int**|  | [optional] [default to 20]

### Return type

[**PaginatedNoteMetaResponse**](PaginatedNoteMetaResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getTag**
> SuccessResponse getTag(id)

Get a tag by ID

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getTag(id);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->getTag: $e\n');
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

# **getTagChildren**
> SuccessResponse getTagChildren(id)

Get direct children of a tag

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getTagChildren(id);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->getTagChildren: $e\n');
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

# **getTagHierarchy**
> SuccessResponse getTagHierarchy(id)

Get full tag hierarchy (ancestors and descendants)

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getTagHierarchy(id);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->getTagHierarchy: $e\n');
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

# **getTagStats**
> SuccessResponse getTagStats(id)

Get tag statistics

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getTagStats(id);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->getTagStats: $e\n');
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

# **getTagsByNote**
> SuccessResponse getTagsByNote(noteId)

Get all tags associated with a note

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final noteId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getTagsByNote(noteId);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->getTagsByNote: $e\n');
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

# **getTopTags**
> SuccessResponse getTopTags(limit)

Get most frequently used tags

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final limit = 56; // int | 

try {
    final result = api_instance.getTopTags(limit);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->getTopTags: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **limit** | **int**|  | [optional] [default to 10]

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **linkTagToNote**
> SuccessResponse linkTagToNote(id, noteId)

Link a tag to a note

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Tag ID
final noteId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Note ID

try {
    final result = api_instance.linkTagToNote(id, noteId);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->linkTagToNote: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**| Tag ID | 
 **noteId** | **String**| Note ID | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listTags**
> PaginatedTagResponse listTags(page, pageSize, search)

List tags with pagination

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final page = 56; // int | 
final pageSize = 56; // int | 
final search = search_example; // String | 

try {
    final result = api_instance.listTags(page, pageSize, search);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->listTags: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **page** | **int**|  | [optional] [default to 1]
 **pageSize** | **int**|  | [optional] [default to 20]
 **search** | **String**|  | [optional] 

### Return type

[**PaginatedTagResponse**](PaginatedTagResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **mergeTags**
> SuccessResponse mergeTags(mergeTagsRequest)

Merge two tags (source into target)

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final mergeTagsRequest = MergeTagsRequest(); // MergeTagsRequest | 

try {
    final result = api_instance.mergeTags(mergeTagsRequest);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->mergeTags: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **mergeTagsRequest** | [**MergeTagsRequest**](MergeTagsRequest.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **splitTag**
> SuccessResponse splitTag(splitTagRequest)

Split a tag, creating a new tag for selected notes

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final splitTagRequest = SplitTagRequest(); // SplitTagRequest | 

try {
    final result = api_instance.splitTag(splitTagRequest);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->splitTag: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **splitTagRequest** | [**SplitTagRequest**](SplitTagRequest.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unlinkTagFromNote**
> SuccessResponse unlinkTagFromNote(id, noteId)

Unlink a tag from a note

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Tag ID
final noteId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Note ID

try {
    final result = api_instance.unlinkTagFromNote(id, noteId);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->unlinkTagFromNote: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**| Tag ID | 
 **noteId** | **String**| Note ID | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateTag**
> SuccessResponse updateTag(id, tagMeta)

Update a tag

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = TagsApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final tagMeta = TagMeta(); // TagMeta | 

try {
    final result = api_instance.updateTag(id, tagMeta);
    print(result);
} catch (e) {
    print('Exception when calling TagsApi->updateTag: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 
 **tagMeta** | [**TagMeta**](TagMeta.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

