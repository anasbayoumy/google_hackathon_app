import 'package:json_annotation/json_annotation.dart';

part 'ai_response.g.dart';

@JsonSerializable()
class AiResponse {
  final String smsDraft;
  final List<String> guidanceSteps;

  AiResponse({required this.smsDraft, required this.guidanceSteps});

  factory AiResponse.fromJson(Map<String, dynamic> json) =>
      _$AiResponseFromJson(json);
  Map<String, dynamic> toJson() => _$AiResponseToJson(this);
}
