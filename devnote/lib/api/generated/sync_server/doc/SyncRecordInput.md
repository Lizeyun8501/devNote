# devnote_sync_api.model.SyncRecordInput

## Load the model package
```dart
import 'package:devnote_sync_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**noteId** | **String** | Note identifier | 
**action** | **String** | Action type for this record | 
**version** | **int** | Client-side version number | [optional] 
**payload** | **String** | Note content payload (CRDT or plain text) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


