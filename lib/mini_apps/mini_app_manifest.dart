import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const miniAppApiVersion = 1;

class MiniAppManifest {
  MiniAppManifest._(
    this.id,
    this.version,
    this.icon,
    this.names,
    this.descriptions,
    this.requests,
  );

  final String id;
  final String version;
  final String icon;
  final Map<String, String> names;
  final Map<String, String> descriptions;
  final Map<String, MiniAppRequest> requests;

  String get asset => 'assets/webf/$id.html';
  String name(String locale) => _localized(names, locale);
  String description(String locale) => _localized(descriptions, locale);

  static String _localized(Map<String, String> values, String locale) =>
      values[locale] ??
      values[locale.split('-').first] ??
      values['en-US'] ??
      values.values.first;

  factory MiniAppManifest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (json['apiVersion'] != miniAppApiVersion ||
        id is! String ||
        !RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(id) ||
        json['version'] is! String ||
        (json['version'] as String).isEmpty ||
        json['icon'] is! String ||
        (json['icon'] as String).isEmpty) {
      throw const FormatException('Invalid mini app manifest');
    }
    Map<String, String> localized(dynamic value) {
      if (value is! Map ||
          value.isEmpty ||
          value.values.any((v) => v is! String || v.isEmpty)) {
        throw const FormatException('Invalid mini app labels');
      }
      return Map<String, String>.unmodifiable(value.cast<String, String>());
    }

    final rawRequests = json['requests'] ?? <String, dynamic>{};
    if (rawRequests is! Map<String, dynamic>) {
      throw const FormatException('Invalid mini app requests');
    }
    return MiniAppManifest._(
      id,
      json['version'] as String,
      json['icon'] as String,
      localized(json['name']),
      localized(json['description']),
      Map.unmodifiable(
        rawRequests.map(
          (key, value) => MapEntry(key, MiniAppRequest.fromJson(value)),
        ),
      ),
    );
  }
}

class MiniAppRequest {
  const MiniAppRequest._(this.method, this.path);
  final String method;
  final String path;

  factory MiniAppRequest.fromJson(dynamic json) {
    if (json is! Map ||
        !const {
          'GET',
          'POST',
          'PUT',
          'PATCH',
          'DELETE',
        }.contains(json['method']) ||
        json['path'] is! String ||
        !RegExp(
          r'^/[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)*$',
        ).hasMatch(json['path'] as String)) {
      throw const FormatException('Invalid mini app request');
    }
    return MiniAppRequest._(json['method'] as String, json['path'] as String);
  }
}

List<MiniAppManifest> parseMiniAppCatalog(String source) {
  final json = jsonDecode(source);
  if (json is! Map ||
      json['apiVersion'] != miniAppApiVersion ||
      json['apps'] is! List) {
    throw const FormatException('Invalid mini app catalog');
  }
  final apps = (json['apps'] as List)
      .map((value) => MiniAppManifest.fromJson(value as Map<String, dynamic>))
      .toList();
  if (apps.map((app) => app.id).toSet().length != apps.length) {
    throw const FormatException('Duplicate mini app ID');
  }
  return List.unmodifiable(apps);
}

final miniAppCatalogProvider = FutureProvider<List<MiniAppManifest>>(
  (ref) async => parseMiniAppCatalog(
    await rootBundle.loadString('assets/webf/manifest.json'),
  ),
);
