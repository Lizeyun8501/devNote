# devnote_sync_api.model.PullResponse

## Load the model package
```dart
import 'package:devnote_sync_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**records** | [**List<SyncRecord>**](SyncRecord.md) | List of sync records | [optional] [default to const []]
**latestVersion** | **int** | Latest version number on the server | [optional] 
**hasMore** | **bool** | Whether more records are available | [optional] 
**limit** | **int** | Number of records returned in this response | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


