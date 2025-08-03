// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AiResponse _$AiResponseFromJson(Map<String, dynamic> json) => AiResponse(
      smsDraft: json['smsDraft'] as String,
      guidanceSteps: (json['guidanceSteps'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$AiResponseToJson(AiResponse instance) =>
    <String, dynamic>{
      'smsDraft': instance.smsDraft,
      'guidanceSteps': instance.guidanceSteps,
    };
