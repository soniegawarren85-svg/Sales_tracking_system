import 'dart:math';

String generateStrongPassword() {
  final random = Random.secure();
  const groups = [
    'ABCDEFGHJKLMNPQRSTUVWXYZ',
    'abcdefghijkmnopqrstuvwxyz',
    '23456789',
    '!@#%*-_+',
  ];
  final characters = groups.join();
  final result = [
    for (final group in groups) group[random.nextInt(group.length)],
  ];
  while (result.length < 20) {
    result.add(characters[random.nextInt(characters.length)]);
  }
  result.shuffle(random);
  return result.join();
}
