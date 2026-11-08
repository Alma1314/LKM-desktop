// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'websocket_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WebSocketState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSocketState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState()';
}


}

/// @nodoc
class $WebSocketStateCopyWith<$Res>  {
$WebSocketStateCopyWith(WebSocketState _, $Res Function(WebSocketState) __);
}


/// Adds pattern-matching-related methods to [WebSocketState].
extension WebSocketStatePatterns on WebSocketState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _Connected value)?  connected,TResult Function( _Connecting value)?  connecting,TResult Function( _Disconnected value)?  disconnected,TResult Function( _InternetChanged value)?  internetChanged,TResult Function( _ServerDown value)?  serverDown,TResult Function( _DuplicateDevice value)?  duplicateDevice,TResult Function( _Unauthorized value)?  unauthorized,TResult Function( _Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Connected() when connected != null:
return connected(_that);case _Connecting() when connecting != null:
return connecting(_that);case _Disconnected() when disconnected != null:
return disconnected(_that);case _InternetChanged() when internetChanged != null:
return internetChanged(_that);case _ServerDown() when serverDown != null:
return serverDown(_that);case _DuplicateDevice() when duplicateDevice != null:
return duplicateDevice(_that);case _Unauthorized() when unauthorized != null:
return unauthorized(_that);case _Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _Connected value)  connected,required TResult Function( _Connecting value)  connecting,required TResult Function( _Disconnected value)  disconnected,required TResult Function( _InternetChanged value)  internetChanged,required TResult Function( _ServerDown value)  serverDown,required TResult Function( _DuplicateDevice value)  duplicateDevice,required TResult Function( _Unauthorized value)  unauthorized,required TResult Function( _Error value)  error,}){
final _that = this;
switch (_that) {
case _Connected():
return connected(_that);case _Connecting():
return connecting(_that);case _Disconnected():
return disconnected(_that);case _InternetChanged():
return internetChanged(_that);case _ServerDown():
return serverDown(_that);case _DuplicateDevice():
return duplicateDevice(_that);case _Unauthorized():
return unauthorized(_that);case _Error():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _Connected value)?  connected,TResult? Function( _Connecting value)?  connecting,TResult? Function( _Disconnected value)?  disconnected,TResult? Function( _InternetChanged value)?  internetChanged,TResult? Function( _ServerDown value)?  serverDown,TResult? Function( _DuplicateDevice value)?  duplicateDevice,TResult? Function( _Unauthorized value)?  unauthorized,TResult? Function( _Error value)?  error,}){
final _that = this;
switch (_that) {
case _Connected() when connected != null:
return connected(_that);case _Connecting() when connecting != null:
return connecting(_that);case _Disconnected() when disconnected != null:
return disconnected(_that);case _InternetChanged() when internetChanged != null:
return internetChanged(_that);case _ServerDown() when serverDown != null:
return serverDown(_that);case _DuplicateDevice() when duplicateDevice != null:
return duplicateDevice(_that);case _Unauthorized() when unauthorized != null:
return unauthorized(_that);case _Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  connected,TResult Function()?  connecting,TResult Function()?  disconnected,TResult Function()?  internetChanged,TResult Function()?  serverDown,TResult Function()?  duplicateDevice,TResult Function()?  unauthorized,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Connected() when connected != null:
return connected();case _Connecting() when connecting != null:
return connecting();case _Disconnected() when disconnected != null:
return disconnected();case _InternetChanged() when internetChanged != null:
return internetChanged();case _ServerDown() when serverDown != null:
return serverDown();case _DuplicateDevice() when duplicateDevice != null:
return duplicateDevice();case _Unauthorized() when unauthorized != null:
return unauthorized();case _Error() when error != null:
return error(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  connected,required TResult Function()  connecting,required TResult Function()  disconnected,required TResult Function()  internetChanged,required TResult Function()  serverDown,required TResult Function()  duplicateDevice,required TResult Function()  unauthorized,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case _Connected():
return connected();case _Connecting():
return connecting();case _Disconnected():
return disconnected();case _InternetChanged():
return internetChanged();case _ServerDown():
return serverDown();case _DuplicateDevice():
return duplicateDevice();case _Unauthorized():
return unauthorized();case _Error():
return error(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  connected,TResult? Function()?  connecting,TResult? Function()?  disconnected,TResult? Function()?  internetChanged,TResult? Function()?  serverDown,TResult? Function()?  duplicateDevice,TResult? Function()?  unauthorized,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case _Connected() when connected != null:
return connected();case _Connecting() when connecting != null:
return connecting();case _Disconnected() when disconnected != null:
return disconnected();case _InternetChanged() when internetChanged != null:
return internetChanged();case _ServerDown() when serverDown != null:
return serverDown();case _DuplicateDevice() when duplicateDevice != null:
return duplicateDevice();case _Unauthorized() when unauthorized != null:
return unauthorized();case _Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _Connected implements WebSocketState {
  const _Connected();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Connected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState.connected()';
}


}




/// @nodoc


class _Connecting implements WebSocketState {
  const _Connecting();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Connecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState.connecting()';
}


}




/// @nodoc


class _Disconnected implements WebSocketState {
  const _Disconnected();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Disconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState.disconnected()';
}


}




/// @nodoc


class _InternetChanged implements WebSocketState {
  const _InternetChanged();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InternetChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState.internetChanged()';
}


}




/// @nodoc


class _ServerDown implements WebSocketState {
  const _ServerDown();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ServerDown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState.serverDown()';
}


}




/// @nodoc


class _DuplicateDevice implements WebSocketState {
  const _DuplicateDevice();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DuplicateDevice);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState.duplicateDevice()';
}


}




/// @nodoc


class _Unauthorized implements WebSocketState {
  const _Unauthorized();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Unauthorized);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WebSocketState.unauthorized()';
}


}




/// @nodoc


class _Error implements WebSocketState {
  const _Error(this.message);
  

 final  String message;

/// Create a copy of WebSocketState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ErrorCopyWith<_Error> get copyWith => __$ErrorCopyWithImpl<_Error>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'WebSocketState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class _$ErrorCopyWith<$Res> implements $WebSocketStateCopyWith<$Res> {
  factory _$ErrorCopyWith(_Error value, $Res Function(_Error) _then) = __$ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class __$ErrorCopyWithImpl<$Res>
    implements _$ErrorCopyWith<$Res> {
  __$ErrorCopyWithImpl(this._self, this._then);

  final _Error _self;
  final $Res Function(_Error) _then;

/// Create a copy of WebSocketState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(_Error(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
