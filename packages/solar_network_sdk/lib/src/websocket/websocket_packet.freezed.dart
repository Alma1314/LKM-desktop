// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'websocket_packet.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WebSocketPacket {

 String get type; Map<String, dynamic>? get data; String? get endpoint; String? get errorMessage;
/// Create a copy of WebSocketPacket
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebSocketPacketCopyWith<WebSocketPacket> get copyWith => _$WebSocketPacketCopyWithImpl<WebSocketPacket>(this as WebSocketPacket, _$identity);

  /// Serializes this WebSocketPacket to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as WebSocketPacket;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSocketPacket&&(identical(other.type, _this.type) || other.type == _this.type)&&const DeepCollectionEquality().equals(other.data, _this.data)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as WebSocketPacket;
  return Object.hash(runtimeType,_this.type,const DeepCollectionEquality().hash(_this.data),_this.endpoint,_this.errorMessage);
}

@override
String toString() {
  final _this = this as WebSocketPacket;
  return 'WebSocketPacket(type: ${_this.type}, data: ${_this.data}, endpoint: ${_this.endpoint}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $WebSocketPacketCopyWith<$Res>  {
  factory $WebSocketPacketCopyWith(WebSocketPacket value, $Res Function(WebSocketPacket) _then) = _$WebSocketPacketCopyWithImpl;
@useResult
$Res call({
 String type, Map<String, dynamic>? data, String? endpoint, String? errorMessage
});




}
/// @nodoc
class _$WebSocketPacketCopyWithImpl<$Res>
    implements $WebSocketPacketCopyWith<$Res> {
  _$WebSocketPacketCopyWithImpl(this._self, this._then);

  final WebSocketPacket _self;
  final $Res Function(WebSocketPacket) _then;

/// Create a copy of WebSocketPacket
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? data = freezed,Object? endpoint = freezed,Object? errorMessage = freezed,}) {
  return _then(WebSocketPacket(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,endpoint: freezed == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [WebSocketPacket].
extension WebSocketPacketPatterns on WebSocketPacket {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WebSocketPacket value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WebSocketPacket() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WebSocketPacket value)  $default,){
final _that = this;
switch (_that) {
case _WebSocketPacket():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WebSocketPacket value)?  $default,){
final _that = this;
switch (_that) {
case _WebSocketPacket() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  Map<String, dynamic>? data,  String? endpoint,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WebSocketPacket() when $default != null:
return $default(_that.type,_that.data,_that.endpoint,_that.errorMessage);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  Map<String, dynamic>? data,  String? endpoint,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _WebSocketPacket():
return $default(_that.type,_that.data,_that.endpoint,_that.errorMessage);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  Map<String, dynamic>? data,  String? endpoint,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _WebSocketPacket() when $default != null:
return $default(_that.type,_that.data,_that.endpoint,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WebSocketPacket implements WebSocketPacket {
  const _WebSocketPacket({required this.type, required  Map<String, dynamic>? data, this.endpoint, this.errorMessage}): _data = data;
  factory _WebSocketPacket.fromJson(Map<String, dynamic> json) => _$WebSocketPacketFromJson(json);

@override final  String type;
 final  Map<String, dynamic>? _data;
@override Map<String, dynamic>? get data {
  final value = _data;
  if (value == null) return null;
  if (_data is EqualUnmodifiableMapView) return _data;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  String? endpoint;
@override final  String? errorMessage;

/// Create a copy of WebSocketPacket
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WebSocketPacketCopyWith<_WebSocketPacket> get copyWith => __$WebSocketPacketCopyWithImpl<_WebSocketPacket>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WebSocketPacketToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WebSocketPacket&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.data, _data)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,type,const DeepCollectionEquality().hash(_data),endpoint,errorMessage);
}

@override
String toString() {
    return 'WebSocketPacket(type: $type, data: $data, endpoint: $endpoint, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$WebSocketPacketCopyWith<$Res> implements $WebSocketPacketCopyWith<$Res> {
  factory _$WebSocketPacketCopyWith(_WebSocketPacket value, $Res Function(_WebSocketPacket) _then) = __$WebSocketPacketCopyWithImpl;
@override @useResult
$Res call({
 String type, Map<String, dynamic>? data, String? endpoint, String? errorMessage
});




}
/// @nodoc
class __$WebSocketPacketCopyWithImpl<$Res>
    implements _$WebSocketPacketCopyWith<$Res> {
  __$WebSocketPacketCopyWithImpl(this._self, this._then);

  final _WebSocketPacket _self;
  final $Res Function(_WebSocketPacket) _then;

/// Create a copy of WebSocketPacket
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? data = freezed,Object? endpoint = freezed,Object? errorMessage = freezed,}) {
  return _then(_WebSocketPacket(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,data: freezed == data ? _self._data : data // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,endpoint: freezed == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
