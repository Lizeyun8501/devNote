// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'block_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BlockModel _$BlockModelFromJson(Map<String, dynamic> json) => _BlockModel(
      id: json['id'] as String,
      noteId: json['note_id'] as String,
      blockType: json['block_type'] as String,
      content: json['content'] as String,
      position: (json['position'] as num).toInt(),
    );

Map<String, dynamic> _$BlockModelToJson(_BlockModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'note_id': instance.noteId,
      'block_type': instance.blockType,
      'content': instance.content,
      'position': instance.position,
    };
