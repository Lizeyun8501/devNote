# devnote_business_api.model.ValidationReport

## Load the model package
```dart
import 'package:devnote_business_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**targetId** | **String** |  | [optional] 
**type** | **String** | Type of validated entity (note, folder, tag, knowledge) | [optional] 
**results** | [**List<ValidationResult>**](ValidationResult.md) |  | [optional] [default to const []]
**passed** | **bool** | Overall validation pass status | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


