import 'package:freezed_annotation/freezed_annotation.dart';

part 'block_model.freezed.dart';
part 'block_model.g.dart';

@Freezed()
abstract class BlockModel with _$BlockModel {
  const BlockModel._();

  const factory BlockModel({
    required String id,
    @JsonKey(name: 'note_id') required String noteId,
    @JsonKey(name: 'block_type') required String blockType,
    required String content,
    required int position,
  }) = _BlockModel;

  factory BlockModel.fromJson(Map<String, dynamic> json) =>
      _$BlockModelFromJson(json);
}
