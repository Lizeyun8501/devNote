# devnote_business_api.model.GraphMetrics

## Load the model package
```dart
import 'package:devnote_business_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**totalNodes** | **int** |  | [optional] 
**totalEdges** | **int** |  | [optional] 
**density** | **double** |  | [optional] 
**orphanCount** | **int** |  | [optional] 
**clusterCount** | **int** |  | [optional] 
**avgDegree** | **double** |  | [optional] 
**degreeCentrality** | **Map<String, double>** |  | [optional] [default to const {}]
**pageRank** | **Map<String, double>** |  | [optional] [default to const {}]
**betweenness** | **Map<String, double>** |  | [optional] [default to const {}]
**clusters** | [**Map<String, List<String>>**](List.md) |  | [optional] [default to const {}]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


