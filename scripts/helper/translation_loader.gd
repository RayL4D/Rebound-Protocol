# =============================================================
# translation_loader.gd — Permet d'importer les traductions présentes sur le google sheets
# Auteur : Kevin SIDER
# =============================================================

@tool
extends EditorScript

const SPREADSHEET_ID = "1YTi1aiBjaaLMTd9oKIZl4AAOC4U5l1lBlrrkBNSKPVs"
const SAVE_PATH = "res://data/translations.csv"

func _run() -> void:
	print("--- Début du téléchargement ---")

	var http := HTTPClient.new()
	var err := http.connect_to_host("docs.google.com", 443, TLSOptions.client())
	if err != OK:
		printerr("Connexion impossible : ", err)
		return

	# Attendre la connexion (max 5s)
	var tries := 0
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http.poll()
		OS.delay_msec(100)
		tries += 1
		if tries > 50:
			printerr("Timeout : impossible de se connecter à Google.")
			return

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		printerr("Connexion échouée. Statut : ", http.get_status())
		return

	# Envoyer la requête GET
	var path := "/spreadsheets/d/%s/export?format=csv" % SPREADSHEET_ID
	err = http.request(HTTPClient.METHOD_GET, path, [
		"User-Agent: Godot",
		"Accept: text/csv"
	])
	if err != OK:
		printerr("Erreur lors de la requête : ", err)
		return

	# Attendre la réponse
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		OS.delay_msec(100)

	if not http.has_response():
		printerr("Pas de réponse reçue.")
		return

	var response_code := http.get_response_code()
	print("Code HTTP : ", response_code)

	# Suivre les redirections (Google redirige souvent)
	var redirect_count := 0
	while response_code in [301, 302, 303, 307, 308] and redirect_count < 5:
		var headers := http.get_response_headers_as_dictionary()
		var location: String = headers.get("location", headers.get("Location", ""))
		if location.is_empty():
			printerr("Redirection sans Location header.")
			break

		print("Redirection → ", location)
		redirect_count += 1

		# Parser la nouvelle URL
		var new_host: String
		var new_path: String
		if location.begins_with("https://"):
			location = location.substr(8)
			var slash := location.find("/")
			new_host = location.substr(0, slash)
			new_path = location.substr(slash)
		elif location.begins_with("/"):
			new_host = "docs.google.com"
			new_path = location
		else:
			printerr("Format de redirection non supporté : ", location)
			break

		# Lire et vider le body avant de reconnecter
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			http.read_response_body_chunk()
			OS.delay_msec(10)

		http = HTTPClient.new()
		err = http.connect_to_host(new_host, 443, TLSOptions.client())
		if err != OK:
			printerr("Connexion redirection impossible : ", err)
			return

		tries = 0
		while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
			http.poll()
			OS.delay_msec(100)
			tries += 1
			if tries > 50:
				printerr("Timeout redirection.")
				return

		err = http.request(HTTPClient.METHOD_GET, new_path, [
			"User-Agent: Godot",
			"Accept: text/csv"
		])
		if err != OK:
			printerr("Erreur requête redirection : ", err)
			return

		while http.get_status() == HTTPClient.STATUS_REQUESTING:
			http.poll()
			OS.delay_msec(100)

		response_code = http.get_response_code()
		print("Nouveau code HTTP : ", response_code)

	if response_code != 200:
		printerr("Échec final. Code HTTP : ", response_code)
		return

	# Lire le body complet
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			body.append_array(chunk)
		else:
			OS.delay_msec(10)

	var content := body.get_string_from_utf8()

	if content.begins_with("<!DOCTYPE") or content.contains("<html"):
		printerr("ERREUR : contenu HTML reçu. Vérifiez les permissions de partage du Google Sheet (lien public).")
		return

	if content.is_empty():
		printerr("ERREUR : contenu vide reçu.")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		printerr("Impossible d'écrire dans : ", SAVE_PATH)
		return

	file.store_string(content)
	file.close()
	print("Succès : translations.csv mis à jour (", content.length(), " caractères)")
	EditorInterface.get_resource_filesystem().scan()
	print("--- Terminé ---")
