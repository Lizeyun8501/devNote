# devnote_business_api.api.MetadataApi

## Load the API package
```dart
import 'package:devnote_business_api/api.dart';
```

All URIs are relative to *http://localhost:8081*

Method | HTTP request | Description
------------- | ------------- | -------------
[**batchCreateMetadata**](MetadataApi.md#batchcreatemetadata) | **POST** /api/v1/metadata/batch | Batch create note metadata
[**batchDeleteMetadata**](MetadataApi.md#batchdeletemetadata) | **POST** /api/v1/metadata/batch-delete | Batch delete note metadata
[**createMetadata**](MetadataApi.md#createmetadata) | **POST** /api/v1/metadata | Create note metadata
[**deleteMetadata**](MetadataApi.md#deletemetadata) | **DELETE** /api/v1/metadata/{id} | Delete note metadata
[**filterMetadata**](MetadataApi.md#filtermetadata) | **GET** /api/v1/metadata/filter | Filter note metadata by attributes
[**getMetadata**](MetadataApi.md#getmetadata) | **GET** /api/v1/metadata/{id} | Get note metadata by ID
[**listMetadata**](MetadataApi.md#listmetadata) | **GET** /api/v1/metadata | List note metadata with pagination
[**updateMetadata**](MetadataApi.md#updatemetadata) | **PUT** /api/v1/metadata/{id} | Update note metadata


# **batchCreateMetadata**
> SuccessResponse batchCreateMetadata(batchCreateMetadataRequest)

Batch create note metadata

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final batchCreateMetadataRequest = BatchCreateMetadataRequest(); // BatchCreateMetadataRequest | 

try {
    final result = api_instance.batchCreateMetadata(batchCreateMetadataRequest);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->batchCreateMetadata: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **batchCreateMetadataRequest** | [**BatchCreateMetadataRequest**](BatchCreateMetadataRequest.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **batchDeleteMetadata**
> SuccessResponse batchDeleteMetadata(batchDeleteMetadataRequest)

Batch delete note metadata

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final batchDeleteMetadataRequest = BatchDeleteMetadataRequest(); // BatchDeleteMetadataRequest | 

try {
    final result = api_instance.batchDeleteMetadata(batchDeleteMetadataRequest);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->batchDeleteMetadata: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **batchDeleteMetadataRequest** | [**BatchDeleteMetadataRequest**](BatchDeleteMetadataRequest.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createMetadata**
> SuccessResponse createMetadata(noteMeta)

Create note metadata

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final noteMeta = NoteMeta(); // NoteMeta | 

try {
    final result = api_instance.createMetadata(noteMeta);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->createMetadata: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **noteMeta** | [**NoteMeta**](NoteMeta.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteMetadata**
> SuccessResponse deleteMetadata(id)

Delete note metadata

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.deleteMetadata(id);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->deleteMetadata: $e\n');
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

# **filterMetadata**
> PaginatedNoteMetaResponse filterMetadata(format, author, language, page, pageSize)

Filter note metadata by attributes

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final format = format_example; // String | 
final author = author_example; // String | 
final language = language_example; // String | 
final page = 56; // int | 
final pageSize = 56; // int | 

try {
    final result = api_instance.filterMetadata(format, author, language, page, pageSize);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->filterMetadata: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **format** | **String**|  | [optional] 
 **author** | **String**|  | [optional] 
 **language** | **String**|  | [optional] 
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

# **getMetadata**
> SuccessResponse getMetadata(id)

Get note metadata by ID

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getMetadata(id);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->getMetadata: $e\n');
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

# **listMetadata**
> PaginatedNoteMetaResponse listMetadata(page, pageSize, search)

List note metadata with pagination

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final page = 56; // int | 
final pageSize = 56; // int | 
final search = search_example; // String | 

try {
    final result = api_instance.listMetadata(page, pageSize, search);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->listMetadata: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **page** | **int**|  | [optional] [default to 1]
 **pageSize** | **int**|  | [optional] [default to 20]
 **search** | **String**|  | [optional] 

### Return type

[**PaginatedNoteMetaResponse**](PaginatedNoteMetaResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateMetadata**
> SuccessResponse updateMetadata(id, noteMeta)

Update note metadata

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = MetadataApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final noteMeta = NoteMeta(); // NoteMeta | 

try {
    final result = api_instance.updateMetadata(id, noteMeta);
    print(result);
} catch (e) {
    print('Exception when calling MetadataApi->updateMetadata: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 
 **noteMeta** | [**NoteMeta**](NoteMeta.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

