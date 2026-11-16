import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/login_options.dart';

void main() {
  test('no configured OIDC providers does not prevent password login', () {
    expect(parseLoginOptions('["common-oidc/null"]'), isEmpty);
    expect(parseLoginOptions('null'), isEmpty);
    expect(parseLoginOptions('[]'), isEmpty);
  });

  test('configured OIDC providers remain available', () {
    expect(parseLoginOptions('["oidc/example"]'), [
      {'name': 'example'}
    ]);
    expect(parseLoginOptions(r'["common-oidc/[{\"name\":\"example\"}]"]'), [
      {'name': 'example'}
    ]);
  });

  test('invalid provider responses still report an error', () {
    expect(() => parseLoginOptions('{}'), throwsFormatException);
    expect(
        () => parseLoginOptions('["common-oidc/{}"]'), throwsFormatException);
  });
}
