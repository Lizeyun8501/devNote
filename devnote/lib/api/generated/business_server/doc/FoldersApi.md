# devnote_business_api.api.FoldersApi

## Load the API package
```dart
import 'package:devnote_business_api/api.dart';
```

All URIs are relative to *http://localhost:8081*

Method | HTTP request | Description
------------- | ------------- | -------------
[**copyFolder**](FoldersApi.md#copyfolder) | **POST** /api/v1/folders/{id}/copy | Copy a folder to a new parent
[**createFolder**](FoldersApi.md#createfolder) | **POST** /api/v1/folders | Create a folder
[**deleteFolder**](FoldersApi.md#deletefolder) | **DELETE** /api/v1/folders/{id} | Delete a folder
[**getFolder**](FoldersApi.md#getfolder) | **GET** /api/v1/folders/{id} | Get a folder by ID
[**getFolderTree**](FoldersApi.md#getfoldertree) | **GET** /api/v1/folders/tree | Get folder tree structure
[**getNotesByFolder**](FoldersApi.md#getnotesbyfolder) | **GET** /api/v1/folders/{id}/notes | Get all notes in a folder
[**listFolders**](FoldersApi.md#listfolders) | **GET** /api/v1/folders | List folders by parent
[**moveFolder**](FoldersApi.md#movefolder) | **POST** /api/v1/folders/{id}/move | Move a folder to a new parent
[**resolveFolderPath**](FoldersApi.md#resolvefolderpath) | **GET** /api/v1/folders/{id}/path | Resolve the full path of a folder
[**updateFolder**](FoldersApi.md#updatefolder) | **PUT** /api/v1/folders/{id} | Update a folder


# **copyFolder**
> SuccessResponse copyFolder(id, moveFolderRequest)

Copy a folder to a new parent

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final moveFolderRequest = MoveFolderRequest(); // MoveFolderRequest | 

try {
    final result = api_instance.copyFolder(id, moveFolderRequest);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->copyFolder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 
 **moveFolderRequest** | [**MoveFolderRequest**](MoveFolderRequest.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createFolder**
> SuccessResponse createFolder(folderMeta)

Create a folder

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final folderMeta = FolderMeta(); // FolderMeta | 

try {
    final result = api_instance.createFolder(folderMeta);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->createFolder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **folderMeta** | [**FolderMeta**](FolderMeta.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteFolder**
> SuccessResponse deleteFolder(id, cascade)

Delete a folder

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final cascade = true; // bool | Delete child folders recursively

try {
    final result = api_instance.deleteFolder(id, cascade);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->deleteFolder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 
 **cascade** | **bool**| Delete child folders recursively | [optional] [default to false]

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getFolder**
> SuccessResponse getFolder(id)

Get a folder by ID

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getFolder(id);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->getFolder: $e\n');
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

# **getFolderTree**
> SuccessResponse getFolderTree(parentId)

Get folder tree structure

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final parentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.getFolderTree(parentId);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->getFolderTree: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **parentId** | **String**|  | [optional] 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getNotesByFolder**
> PaginatedNoteMetaResponse getNotesByFolder(id, page, pageSize)

Get all notes in a folder

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final page = 56; // int | 
final pageSize = 56; // int | 

try {
    final result = api_instance.getNotesByFolder(id, page, pageSize);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->getNotesByFolder: $e\n');
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

# **listFolders**
> SuccessResponse listFolders(parentId)

List folders by parent

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final parentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.listFolders(parentId);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->listFolders: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **parentId** | **String**|  | [optional] 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **moveFolder**
> SuccessResponse moveFolder(id, moveFolderRequest)

Move a folder to a new parent

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final moveFolderRequest = MoveFolderRequest(); // MoveFolderRequest | 

try {
    final result = api_instance.moveFolder(id, moveFolderRequest);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->moveFolder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 
 **moveFolderRequest** | [**MoveFolderRequest**](MoveFolderRequest.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **resolveFolderPath**
> SuccessResponse resolveFolderPath(id)

Resolve the full path of a folder

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final result = api_instance.resolveFolderPath(id);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->resolveFolderPath: $e\n');
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

# **updateFolder**
> SuccessResponse updateFolder(id, folderMeta)

Update a folder

### Example
```dart
import 'package:devnote_business_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = FoldersApi();
final id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final folderMeta = FolderMeta(); // FolderMeta | 

try {
    final result = api_instance.updateFolder(id, folderMeta);
    print(result);
} catch (e) {
    print('Exception when calling FoldersApi->updateFolder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 
 **folderMeta** | [**FolderMeta**](FolderMeta.md)|  | 

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

