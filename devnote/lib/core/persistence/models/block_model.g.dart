// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'block_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$BlockModelImpl _$$BlockModelImplFromJson(Map<String, dynamic> json) =>
    _$BlockModelImpl(
      id: json['id'] as String,
      noteId: json['note_id'] as String,
      blockType: json['block_type'] as String,
      content: json['content'] as String,
      position: (json['position'] as num).toInt(),
    );

Map<String, dynamic> _$$BlockModelImplToJson(_$BlockModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'note_id': instance.noteId,
      'block_type': instance.blockType,
      'content': instance.content,
      'position': instance.position,
    };
