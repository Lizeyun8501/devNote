//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;


class SrpAuthApi {
  SrpAuthApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Initiate SRP authentication
  ///
  /// Start the SRP authentication flow. Server returns salt and public ephemeral value B.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [SRPInitRequest] sRPInitRequest (required):
  Future<Response> srpInitWithHttpInfo(SRPInitRequest sRPInitRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/srp/init';

    // ignore: prefer_final_locals
    Object? postBody = sRPInitRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Initiate SRP authentication
  ///
  /// Start the SRP authentication flow. Server returns salt and public ephemeral value B.
  ///
  /// Parameters:
  ///
  /// * [SRPInitRequest] sRPInitRequest (required):
  Future<SRPInitResponse?> srpInit(SRPInitRequest sRPInitRequest, { Future<void>? abortTrigger, }) async {
    final response = await srpInitWithHttpInfo(sRPInitRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SRPInitResponse',) as SRPInitResponse;
    
    }
    return null;
  }

  /// Register with SRP zero-knowledge protocol
  ///
  /// Register a new user using the Secure Remote Password (SRP) protocol.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [SRPRegisterRequest] sRPRegisterRequest (required):
  Future<Response> srpRegisterWithHttpInfo(SRPRegisterRequest sRPRegisterRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/srp/register';

    // ignore: prefer_final_locals
    Object? postBody = sRPRegisterRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Register with SRP zero-knowledge protocol
  ///
  /// Register a new user using the Secure Remote Password (SRP) protocol.
  ///
  /// Parameters:
  ///
  /// * [SRPRegisterRequest] sRPRegisterRequest (required):
  Future<SrpRegister201Response?> srpRegister(SRPRegisterRequest sRPRegisterRequest, { Future<void>? abortTrigger, }) async {
    final response = await srpRegisterWithHttpInfo(sRPRegisterRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SrpRegister201Response',) as SrpRegister201Response;
    
    }
    return null;
  }

  /// Verify SRP client proof
  ///
  /// Submit client's public ephemeral A and proof M1. Server returns M2 proof and session token.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [SRPVerifyRequest] sRPVerifyRequest (required):
  Future<Response> srpVerifyWithHttpInfo(SRPVerifyRequest sRPVerifyRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/srp/verify';

    // ignore: prefer_final_locals
    Object? postBody = sRPVerifyRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Verify SRP client proof
  ///
  /// Submit client's public ephemeral A and proof M1. Server returns M2 proof and session token.
  ///
  /// Parameters:
  ///
  /// * [SRPVerifyRequest] sRPVerifyRequest (required):
  Future<SRPVerifyResponse?> srpVerify(SRPVerifyRequest sRPVerifyRequest, { Future<void>? abortTrigger, }) async {
    final response = await srpVerifyWithHttpInfo(sRPVerifyRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SRPVerifyResponse',) as SRPVerifyResponse;
    
    }
    return null;
  }
}
