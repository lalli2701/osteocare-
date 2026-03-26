class LanguageChangeNotifier {
	int _version = 0;

	int get version => _version;

	void notifyLanguageChanged() {
		_version += 1;
	}

	void reset() {
		_version = 0;
	}
}

final languageChangeProvider = LanguageChangeNotifier();
