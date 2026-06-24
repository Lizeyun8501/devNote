# devnote_sync_api.api.SrpAuthApi

## Load the API package
```dart
import 'package:devnote_sync_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**srpInit**](SrpAuthApi.md#srpinit) | **POST** /api/v1/auth/srp/init | Initiate SRP authentication
[**srpRegister**](SrpAuthApi.md#srpregister) | **POST** /api/v1/auth/srp/register | Register with SRP zero-knowledge protocol
[**srpVerify**](SrpAuthApi.md#srpverify) | **POST** /api/v1/auth/srp/verify | Verify SRP client proof


# **srpInit**
> SRPInitResponse srpInit(sRPInitRequest)

Initiate SRP authentication

Start the SRP authentication flow. Server returns salt and public ephemeral value B.

### Example
```dart
import 'package:devnote_sync_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = SrpAuthApi();
final sRPInitRequest = SRPInitRequest(); // SRPInitRequest | 

try {
    final result = api_instance.srpInit(sRPInitRequest);
    print(result);
} catch (e) {
    print('Exception when calling SrpAuthApi->srpInit: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **sRPInitRequest** | [**SRPInitRequest**](SRPInitRequest.md)|  | 

### Return type

[**SRPInitResponse**](SRPInitResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **srpRegister**
> SrpRegister201Response srpRegister(sRPRegisterRequest)

Register with SRP zero-knowledge protocol

Register a new user using the Secure Remote Password (SRP) protocol.

### Example
```dart
import 'package:devnote_sync_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = SrpAuthApi();
final sRPRegisterRequest = SRPRegisterRequest(); // SRPRegisterRequest | 

try {
    final result = api_instance.srpRegister(sRPRegisterRequest);
    print(result);
} catch (e) {
    print('Exception when calling SrpAuthApi->srpRegister: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **sRPRegisterRequest** | [**SRPRegisterRequest**](SRPRegisterRequest.md)|  | 

### Return type

[**SrpRegister201Response**](SrpRegister201Response.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **srpVerify**
> SRPVerifyResponse srpVerify(sRPVerifyRequest)

Verify SRP client proof

Submit client's public ephemeral A and proof M1. Server returns M2 proof and session token.

### Example
```dart
import 'package:devnote_sync_api/api.dart';
// TODO Configure HTTP Bearer authorization: BearerAuth
// Case 1. Use String Token
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken('YOUR_ACCESS_TOKEN');
// Case 2. Use Function which generate token.
// String yourTokenGeneratorFunction() { ... }
//defaultApiClient.getAuthentication<HttpBearerAuth>('BearerAuth').setAccessToken(yourTokenGeneratorFunction);

final api_instance = SrpAuthApi();
final sRPVerifyRequest = SRPVerifyRequest(); // SRPVerifyRequest | 

try {
    final result = api_instance.srpVerify(sRPVerifyRequest);
    print(result);
} catch (e) {
    print('Exception when calling SrpAuthApi->srpVerify: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **sRPVerifyRequest** | [**SRPVerifyRequest**](SRPVerifyRequest.md)|  | 

### Return type

[**SRPVerifyResponse**](SRPVerifyResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

