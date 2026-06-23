//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;


class SyncApi {
  SyncApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Get sync status for a device
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///   The device identifier
  Future<Response> getSyncStatusWithHttpInfo(String deviceId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/sync/status';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

      queryParams.addAll(_queryParams('', 'device_id', deviceId));

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Get sync status for a device
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///   The device identifier
  Future<SyncStatus?> getSyncStatus(String deviceId, { Future<void>? abortTrigger, }) async {
    final response = await getSyncStatusWithHttpInfo(deviceId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SyncStatus',) as SyncStatus;
    
    }
    return null;
  }

  /// Pull remote changes from the server
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [PullRequest] pullRequest (required):
  ///
  /// * [int] limit:
  ///   Maximum number of records to return (1-1000, default 100)
  Future<Response> pullChangesWithHttpInfo(PullRequest pullRequest, { int? limit, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/sync/pull';

    // ignore: prefer_final_locals
    Object? postBody = pullRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }

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

  /// Pull remote changes from the server
  ///
  /// Parameters:
  ///
  /// * [PullRequest] pullRequest (required):
  ///
  /// * [int] limit:
  ///   Maximum number of records to return (1-1000, default 100)
  Future<PullResponse?> pullChanges(PullRequest pullRequest, { int? limit, Future<void>? abortTrigger, }) async {
    final response = await pullChangesWithHttpInfo(pullRequest, limit: limit, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PullResponse',) as PullResponse;
    
    }
    return null;
  }

  /// Push local changes to the server
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [PushRequest] pushRequest (required):
  Future<Response> pushChangesWithHttpInfo(PushRequest pushRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/sync/push';

    // ignore: prefer_final_locals
    Object? postBody = pushRequest;

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

  /// Push local changes to the server
  ///
  /// Parameters:
  ///
  /// * [PushRequest] pushRequest (required):
  Future<PushResponse?> pushChanges(PushRequest pushRequest, { Future<void>? abortTrigger, }) async {
    final response = await pushChangesWithHttpInfo(pushRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PushResponse',) as PushResponse;
    
    }
    return null;
  }

  /// Resolve a sync conflict
  ///
  /// Manually resolve a sync conflict by providing the chosen data.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ConflictResolution] conflictResolution (required):
  Future<Response> resolveConflictWithHttpInfo(ConflictResolution conflictResolution, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/sync/resolve-conflict';

    // ignore: prefer_final_locals
    Object? postBody = conflictResolution;

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

  /// Resolve a sync conflict
  ///
  /// Manually resolve a sync conflict by providing the chosen data.
  ///
  /// Parameters:
  ///
  /// * [ConflictResolution] conflictResolution (required):
  Future<ResolveConflict200Response?> resolveConflict(ConflictResolution conflictResolution, { Future<void>? abortTrigger, }) async {
    final response = await resolveConflictWithHttpInfo(conflictResolution, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'ResolveConflict200Response',) as ResolveConflict200Response;
    
    }
    return null;
  }
}
