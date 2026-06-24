//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

library devnote_business_api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

part 'api_client.dart';
part 'api_helper.dart';
part 'api_exception.dart';
part 'auth/authentication.dart';
part 'auth/api_key_auth.dart';
part 'auth/oauth.dart';
part 'auth/http_basic_auth.dart';
part 'auth/http_bearer_auth.dart';

part 'api/folders_api.dart';
part 'api/health_api.dart';
part 'api/knowledge_api.dart';
part 'api/metadata_api.dart';
part 'api/tags_api.dart';
part 'api/validation_api.dart';

part 'model/batch_create_metadata_request.dart';
part 'model/batch_delete_metadata_request.dart';
part 'model/business_rule.dart';
part 'model/compute_graph_metrics200_response.dart';
part 'model/create_knowledge_relation_request.dart';
part 'model/error_response.dart';
part 'model/folder_meta.dart';
part 'model/graph_metrics.dart';
part 'model/knowledge_relation.dart';
part 'model/merge_tags_request.dart';
part 'model/move_folder_request.dart';
part 'model/note_meta.dart';
part 'model/paginated_note_meta_response.dart';
part 'model/paginated_tag_response.dart';
part 'model/shortest_path_response.dart';
part 'model/shortest_path_response_data.dart';
part 'model/split_tag_request.dart';
part 'model/success_response.dart';
part 'model/tag_meta.dart';
part 'model/tag_relation.dart';
part 'model/validation_report.dart';
part 'model/validation_result.dart';
part 'model/validation_rule.dart';


/// An [ApiClient] instance that uses the default values obtained from
/// the OpenAPI specification file.
var defaultApiClient = ApiClient();

const _delimiters = {'csv': ',', 'ssv': ' ', 'tsv': '\t', 'pipes': '|'};
const _dateEpochMarker = 'epoch';
const _deepEquality = DeepCollectionEquality();
final _dateFormatter = DateFormat('yyyy-MM-dd');
final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

bool _isEpochMarker(String? pattern) => pattern == _dateEpochMarker || pattern == '/$_dateEpochMarker/';
