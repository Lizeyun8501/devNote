//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;


class FoldersApi {
  FoldersApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Copy a folder to a new parent
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [MoveFolderRequest] moveFolderRequest (required):
  Future<Response> copyFolderWithHttpInfo(String id, MoveFolderRequest moveFolderRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/{id}/copy'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody = moveFolderRequest;

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

  /// Copy a folder to a new parent
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [MoveFolderRequest] moveFolderRequest (required):
  Future<SuccessResponse?> copyFolder(String id, MoveFolderRequest moveFolderRequest, { Future<void>? abortTrigger, }) async {
    final response = await copyFolderWithHttpInfo(id, moveFolderRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Create a folder
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [FolderMeta] folderMeta (required):
  Future<Response> createFolderWithHttpInfo(FolderMeta folderMeta, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders';

    // ignore: prefer_final_locals
    Object? postBody = folderMeta;

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

  /// Create a folder
  ///
  /// Parameters:
  ///
  /// * [FolderMeta] folderMeta (required):
  Future<SuccessResponse?> createFolder(FolderMeta folderMeta, { Future<void>? abortTrigger, }) async {
    final response = await createFolderWithHttpInfo(folderMeta, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Delete a folder
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [bool] cascade:
  ///   Delete child folders recursively
  Future<Response> deleteFolderWithHttpInfo(String id, { bool? cascade, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/{id}'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (cascade != null) {
      queryParams.addAll(_queryParams('', 'cascade', cascade));
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Delete a folder
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [bool] cascade:
  ///   Delete child folders recursively
  Future<SuccessResponse?> deleteFolder(String id, { bool? cascade, Future<void>? abortTrigger, }) async {
    final response = await deleteFolderWithHttpInfo(id, cascade: cascade, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Get a folder by ID
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  Future<Response> getFolderWithHttpInfo(String id, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/{id}'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

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

  /// Get a folder by ID
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  Future<SuccessResponse?> getFolder(String id, { Future<void>? abortTrigger, }) async {
    final response = await getFolderWithHttpInfo(id, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Get folder tree structure
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] parentId:
  Future<Response> getFolderTreeWithHttpInfo({ String? parentId, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/tree';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (parentId != null) {
      queryParams.addAll(_queryParams('', 'parent_id', parentId));
    }

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

  /// Get folder tree structure
  ///
  /// Parameters:
  ///
  /// * [String] parentId:
  Future<SuccessResponse?> getFolderTree({ String? parentId, Future<void>? abortTrigger, }) async {
    final response = await getFolderTreeWithHttpInfo(parentId: parentId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Get all notes in a folder
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [int] page:
  ///
  /// * [int] pageSize:
  Future<Response> getNotesByFolderWithHttpInfo(String id, { int? page, int? pageSize, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/{id}/notes'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (page != null) {
      queryParams.addAll(_queryParams('', 'page', page));
    }
    if (pageSize != null) {
      queryParams.addAll(_queryParams('', 'page_size', pageSize));
    }

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

  /// Get all notes in a folder
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [int] page:
  ///
  /// * [int] pageSize:
  Future<PaginatedNoteMetaResponse?> getNotesByFolder(String id, { int? page, int? pageSize, Future<void>? abortTrigger, }) async {
    final response = await getNotesByFolderWithHttpInfo(id, page: page, pageSize: pageSize, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PaginatedNoteMetaResponse',) as PaginatedNoteMetaResponse;
    
    }
    return null;
  }

  /// List folders by parent
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] parentId:
  Future<Response> listFoldersWithHttpInfo({ String? parentId, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (parentId != null) {
      queryParams.addAll(_queryParams('', 'parent_id', parentId));
    }

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

  /// List folders by parent
  ///
  /// Parameters:
  ///
  /// * [String] parentId:
  Future<SuccessResponse?> listFolders({ String? parentId, Future<void>? abortTrigger, }) async {
    final response = await listFoldersWithHttpInfo(parentId: parentId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Move a folder to a new parent
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [MoveFolderRequest] moveFolderRequest (required):
  Future<Response> moveFolderWithHttpInfo(String id, MoveFolderRequest moveFolderRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/{id}/move'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody = moveFolderRequest;

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

  /// Move a folder to a new parent
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [MoveFolderRequest] moveFolderRequest (required):
  Future<SuccessResponse?> moveFolder(String id, MoveFolderRequest moveFolderRequest, { Future<void>? abortTrigger, }) async {
    final response = await moveFolderWithHttpInfo(id, moveFolderRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Resolve the full path of a folder
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  Future<Response> resolveFolderPathWithHttpInfo(String id, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/{id}/path'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

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

  /// Resolve the full path of a folder
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  Future<SuccessResponse?> resolveFolderPath(String id, { Future<void>? abortTrigger, }) async {
    final response = await resolveFolderPathWithHttpInfo(id, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }

  /// Update a folder
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [FolderMeta] folderMeta (required):
  Future<Response> updateFolderWithHttpInfo(String id, FolderMeta folderMeta, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/folders/{id}'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody = folderMeta;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'PUT',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Update a folder
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  ///
  /// * [FolderMeta] folderMeta (required):
  Future<SuccessResponse?> updateFolder(String id, FolderMeta folderMeta, { Future<void>? abortTrigger, }) async {
    final response = await updateFolderWithHttpInfo(id, folderMeta, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SuccessResponse',) as SuccessResponse;
    
    }
    return null;
  }
}
