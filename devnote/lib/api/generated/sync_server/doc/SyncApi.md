# devnote_sync_api.api.SyncApi

## Load the API package
```dart
import 'package:devnote_sync_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getSyncStatus**](SyncApi.md#getsyncstatus) | **GET** /api/v1/sync/status | Get sync status for a device
[**pullChanges**](SyncApi.md#pullchanges) | **POST** /api/v1/sync/pull | Pull remote changes from the server
[**pushChanges**](SyncApi.md#pushchanges) | **POST** /api/v1/sync/push | Push local changes to the server
[**resolveConflict**](SyncApi.md#resolveconflict) | **POST** /api/v1/sync/resolve-conflict | Resolve a sync conflict


# **getSyncStatus**
> SyncStatus getSyncStatus(deviceId)

Get sync status for a device

### Example
```dart
import 'package:devnote_sync_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = SyncApi();
final deviceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | The device identifier

try {
    final result = api_instance.getSyncStatus(deviceId);
    print(result);
} catch (e) {
    print('Exception when calling SyncApi->getSyncStatus: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **deviceId** | **String**| The device identifier | 

### Return type

[**SyncStatus**](SyncStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **pullChanges**
> PullResponse pullChanges(pullRequest, limit)

Pull remote changes from the server

### Example
```dart
import 'package:devnote_sync_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = SyncApi();
final pullRequest = PullRequest(); // PullRequest | 
final limit = 56; // int | Maximum number of records to return (1-1000, default 100)

try {
    final result = api_instance.pullChanges(pullRequest, limit);
    print(result);
} catch (e) {
    print('Exception when calling SyncApi->pullChanges: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pullRequest** | [**PullRequest**](PullRequest.md)|  | 
 **limit** | **int**| Maximum number of records to return (1-1000, default 100) | [optional] [default to 100]

### Return type

[**PullResponse**](PullResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **pushChanges**
> PushResponse pushChanges(pushRequest)

Push local changes to the server

### Example
```dart
import 'package:devnote_sync_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = SyncApi();
final pushRequest = PushRequest(); // PushRequest | 

try {
    final result = api_instance.pushChanges(pushRequest);
    print(result);
} catch (e) {
    print('Exception when calling SyncApi->pushChanges: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pushRequest** | [**PushRequest**](PushRequest.md)|  | 

### Return type

[**PushResponse**](PushResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **resolveConflict**
> ResolveConflict200Response resolveConflict(conflictResolution)

Resolve a sync conflict

Manually resolve a sync conflict by providing the chosen data.

### Example
```dart
import 'package:devnote_sync_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = SyncApi();
final conflictResolution = ConflictResolution(); // ConflictResolution | 

try {
    final result = api_instance.resolveConflict(conflictResolution);
    print(result);
} catch (e) {
    print('Exception when calling SyncApi->resolveConflict: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **conflictResolution** | [**ConflictResolution**](ConflictResolution.md)|  | 

### Return type

[**ResolveConflict200Response**](ResolveConflict200Response.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

