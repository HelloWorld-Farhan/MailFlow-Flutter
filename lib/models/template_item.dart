import 'dart:convert';

class TemplateItem {
  final String id;
  final String name;
  final String type; // 'Subject' or 'Body'
  final String content;

  TemplateItem({
    required this.id,
    required this.name,
    required this.type,
    required this.content,
  });

  TemplateItem copyWith({
    String? id,
    String? name,
    String? type,
    String? content,
  }) {
    return TemplateItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      content: content ?? this.content,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'content': content,
    };
  }

  factory TemplateItem.fromMap(Map<String, dynamic> map) {
    return TemplateItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? '',
      content: map['content'] ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory TemplateItem.fromJson(String source) => TemplateItem.fromMap(json.decode(source));
}
