# devnote_business_api.api.HealthApi

## Load the API package
```dart
import 'package:devnote_business_api/api.dart';
```

All URIs are relative to *http://localhost:8081*

Method | HTTP request | Description
------------- | ------------- | -------------
[**healthCheck**](HealthApi.md#healthcheck) | **GET** /api/v1/health | Health check


# **healthCheck**
> SuccessResponse healthCheck()

Health check

### Example
```dart
import 'package:devnote_business_api/api.dart';

final api_instance = HealthApi();

try {
    final result = api_instance.healthCheck();
    print(result);
} catch (e) {
    print('Exception when calling HealthApi->healthCheck: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**SuccessResponse**](SuccessResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

