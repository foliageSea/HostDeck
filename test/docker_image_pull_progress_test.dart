import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/docker/docker_image_pull_progress.dart';

void main() {
  test('decodes Docker image pull progress', () {
    final progress = decodeDockerImagePullProgress(
      '{"status":"Downloading","id":"layer-1","progressDetail":{"current":10,"total":20}}',
    );

    expect(progress['status'], 'Downloading');
    expect(progress['id'], 'layer-1');
    expect(progress['progressDetail'], {'current': 10, 'total': 20});
    expect(dockerImagePullError(progress), isNull);
  });

  test('prefers the structured Docker error detail', () {
    final progress = decodeDockerImagePullProgress(
      '{"error":"pull failed","errorDetail":{"message":"registry denied access"}}',
    );

    expect(dockerImagePullError(progress), 'registry denied access');
  });
}
