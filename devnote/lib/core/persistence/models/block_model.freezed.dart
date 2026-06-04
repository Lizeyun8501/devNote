// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'block_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

BlockModel _$BlockModelFromJson(Map<String, dynamic> json) {
  return _BlockModel.fromJson(json);
}

/// @nodoc
mixin _$BlockModel {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'note_id')
  String get noteId => throw _privateConstructorUsedError;
  @JsonKey(name: 'block_type')
  String get blockType => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  int get position => throw _privateConstructorUsedError;

  /// Serializes this BlockModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of BlockModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BlockModelCopyWith<BlockModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BlockModelCopyWith<$Res> {
  factory $BlockModelCopyWith(
    BlockModel value,
    $Res Function(BlockModel) then,
  ) = _$BlockModelCopyWithImpl<$Res, BlockModel>;
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'note_id') String noteId,
    @JsonKey(name: 'block_type') String blockType,
    String content,
    int position,
  });
}

/// @nodoc
class _$BlockModelCopyWithImpl<$Res, $Val extends BlockModel>
    implements $BlockModelCopyWith<$Res> {
  _$BlockModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BlockModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? noteId = null,
    Object? blockType = null,
    Object? content = null,
    Object? position = null,
  }) {
    return _then(
      _value.copyWith(
            id:
                null == id
                    ? _value.id
                    : id // ignore: cast_nullable_to_non_nullable
                        as String,
            noteId:
                null == noteId
                    ? _value.noteId
                    : noteId // ignore: cast_nullable_to_non_nullable
                        as String,
            blockType:
                null == blockType
                    ? _value.blockType
                    : blockType // ignore: cast_nullable_to_non_nullable
                        as String,
            content:
                null == content
                    ? _value.content
                    : content // ignore: cast_nullable_to_non_nullable
                        as String,
            position:
                null == position
                    ? _value.position
                    : position // ignore: cast_nullable_to_non_nullable
                        as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$BlockModelImplCopyWith<$Res>
    implements $BlockModelCopyWith<$Res> {
  factory _$$BlockModelImplCopyWith(
    _$BlockModelImpl value,
    $Res Function(_$BlockModelImpl) then,
  ) = __$$BlockModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'note_id') String noteId,
    @JsonKey(name: 'block_type') String blockType,
    String content,
    int position,
  });
}

/// @nodoc
class __$$BlockModelImplCopyWithImpl<$Res>
    extends _$BlockModelCopyWithImpl<$Res, _$BlockModelImpl>
    implements _$$BlockModelImplCopyWith<$Res> {
  __$$BlockModelImplCopyWithImpl(
    _$BlockModelImpl _value,
    $Res Function(_$BlockModelImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of BlockModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? noteId = null,
    Object? blockType = null,
    Object? content = null,
    Object? position = null,
  }) {
    return _then(
      _$BlockModelImpl(
        id:
            null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                    as String,
        noteId:
            null == noteId
                ? _value.noteId
                : noteId // ignore: cast_nullable_to_non_nullable
                    as String,
        blockType:
            null == blockType
                ? _value.blockType
                : blockType // ignore: cast_nullable_to_non_nullable
                    as String,
        content:
            null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                    as String,
        position:
            null == position
                ? _value.position
                : position // ignore: cast_nullable_to_non_nullable
                    as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$BlockModelImpl implements _BlockModel {
  const _$BlockModelImpl({
    required this.id,
    @JsonKey(name: 'note_id') required this.noteId,
    @JsonKey(name: 'block_type') required this.blockType,
    required this.content,
    required this.position,
  });

  factory _$BlockModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$BlockModelImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'note_id')
  final String noteId;
  @override
  @JsonKey(name: 'block_type')
  final String blockType;
  @override
  final String content;
  @override
  final int position;

  @override
  String toString() {
    return 'BlockModel(id: $id, noteId: $noteId, blockType: $blockType, content: $content, position: $position)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BlockModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.noteId, noteId) || other.noteId == noteId) &&
            (identical(other.blockType, blockType) ||
                other.blockType == blockType) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.position, position) ||
                other.position == position));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, noteId, blockType, content, position);

  /// Create a copy of BlockModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BlockModelImplCopyWith<_$BlockModelImpl> get copyWith =>
      __$$BlockModelImplCopyWithImpl<_$BlockModelImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BlockModelImplToJson(this);
  }
}

abstract class _BlockModel implements BlockModel {
  const factory _BlockModel({
    required final String id,
    @JsonKey(name: 'note_id') required final String noteId,
    @JsonKey(name: 'block_type') required final String blockType,
    required final String content,
    required final int position,
  }) = _$BlockModelImpl;

  factory _BlockModel.fromJson(Map<String, dynamic> json) =
      _$BlockModelImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'note_id')
  String get noteId;
  @override
  @JsonKey(name: 'block_type')
  String get blockType;
  @override
  String get content;
  @override
  int get position;

  /// Create a copy of BlockModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BlockModelImplCopyWith<_$BlockModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
