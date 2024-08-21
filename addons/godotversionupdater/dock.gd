@tool
extends Control

@onready var console = $ScrollContainer/VBoxContainer/Console
@onready var file_dialog = $ScrollContainer/FileDialog
@onready var directory_label = $ScrollContainer/VBoxContainer/DirectoryLocation/DirectoryLabel
@onready var current_version_label = $ScrollContainer/VBoxContainer/VersionData/CurrentVersionLabel
@onready var latest_version_label = $ScrollContainer/VBoxContainer/VersionData/LatestVersionLabel

const GODOT_RELEASES_URL = "https://api.github.com/repos/godotengine/godot/releases/latest"
var selected_path = ""
var current_download_url = ""
var needs_dotnet = false 

func _ready():
	console.text = "Console initialized.\n"  
	var downloads_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	file_dialog.current_path = downloads_path 
	directory_label.text = downloads_path 
	update_current_and_latest_values()
	
func _on_update_button_pressed():
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	http_request.request(GODOT_RELEASES_URL)
	log_to_console("Requesting latest Godot release...")

func _on_request_completed(result, response_code, headers, body): 
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json:
			var latest_release = json
			log_to_console("Latest Godot version: " + latest_release["tag_name"])
			var download_url = _find_correct_asset(latest_release["assets"])
			if download_url != "":
				_download_update(download_url)
				log_to_console("Starting download...")
			else:
				log_to_console("No suitable executable found for download.")
		else:
			log_to_console("Failed to fetch latest version")
		
func _find_correct_asset(assets):
	var os_name = OS.get_name()
	var architecture = Engine.get_architecture_name()
	for asset in assets:
		# Check for Windows OS
		if os_name == "Windows":
			if architecture == "x86_64":
				if needs_dotnet and asset["name"].ends_with("mono_win64.zip"):
					log_to_console("Downloading .NET version for Windows 64-bit.")
					print(asset["browser_download_url"])
					return asset["browser_download_url"]
				elif asset["name"].ends_with("win64.exe.zip"):
					return asset["browser_download_url"]
			elif architecture == "x86":
				if needs_dotnet and asset["name"].ends_with("mono_win32.zip"):
					log_to_console("Downloading .NET version for Windows 32-bit.")
					return asset["browser_download_url"]
				elif asset["name"].ends_with("win32.exe.zip"):
					return asset["browser_download_url"]

		# Check for Linux OS
		if os_name == "Linux":
			if architecture == "x86_64":
				# Check for .NET version first if needed
				if needs_dotnet and asset["name"].ends_with("mono_linux_x86_64.zip"):
					log_to_console("Downloading .NET version for Linux 64-bit.")
					return asset["browser_download_url"]
				elif not needs_dotnet and asset["name"].ends_with("linux.x86_64.zip"):
					log_to_console("Downloading Linux 64-bit version.")
					return asset["browser_download_url"]
			elif architecture == "x86":
				if needs_dotnet and asset["name"].ends_with("mono_linux_x86_32.zip"):
					log_to_console("Downloading .NET version for Linux 32-bit.")
					return asset["browser_download_url"]
				elif not needs_dotnet and asset["name"].ends_with("linux.x86_32.zip"):
					log_to_console("Downloading Linux 32-bit version.")
					return asset["browser_download_url"]
					
		# Check for macOS
		if os_name == "macOS":
			if needs_dotnet and asset["name"].ends_with("mono_macos.universal.zip"):
				return asset["browser_download_url"]  # Ensure this is the full app with Mono
			elif asset["name"].ends_with("macos.universal.zip"):
				return asset["browser_download_url"]

		# Check for Mobile
		if OS.has_feature("Android"):
			if needs_dotnet and asset["name"].ends_with("android_mono.apk"):
				return asset["browser_download_url"]  # Ensure this is the full app with Mono
			elif asset["name"].ends_with("android.apk"):
				return asset["browser_download_url"]
	return ""

func validate_directory():
	if selected_path == "":
		selected_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var dir = DirAccess.open(selected_path)
	if dir:		
		log_to_console("Valid directory found.")
		return selected_path
	else:
		var downloads_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		log_to_console("Invalid directory selected. Defaulting to Downloads: " + downloads_path)
		return downloads_path
		
func _download_update(url: String):
	current_download_url = url
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_download_completed)
	http_request.request(url)

func _on_download_completed(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var valid_path = validate_directory()
		var filename = current_download_url.get_file().get_basename() + ".zip"
		var file_path = "%s/%s" % [valid_path, filename]
		print(file_path)
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			log_to_console("Update downloaded successfully to: " + file_path)
			log_to_console("Extracting...")
			if OS.get_name() == "Windows":
				log_to_console("Extracting...")
				_extract_and_execute(file_path)
			else:
				log_to_console("Download complete. File located at: " + file_path)
				OS.shell_show_in_file_manager(file_path)
	else:
		log_to_console("Download failed with response code: " + str(response_code))

func _extract_and_execute(file_path):
	var zip_reader = ZIPReader.new()
	if zip_reader.open(file_path) != OK:
		log_to_console("Failed to open ZIP file: " + file_path)
		return

	var extracted_path = file_path.get_base_dir() + "/" + file_path.get_file().get_basename().trim_suffix(".zip")
	var dir_access = DirAccess.open(extracted_path)

	if dir_access == null:
		dir_access = DirAccess.open(file_path.get_base_dir())
		if dir_access.make_dir_recursive(extracted_path) != OK:
			log_to_console("Failed to create directory: " + extracted_path)
			return
		dir_access = DirAccess.open(extracted_path)

	for file_in_zip in zip_reader.get_files():
		var full_path = extracted_path + "/" + file_in_zip
		var file_dir = full_path.get_base_dir()
		if DirAccess.open(file_dir) == null:
			DirAccess.open(extracted_path).make_dir_recursive(file_dir)

		var file_access = FileAccess.open(full_path, FileAccess.WRITE)
		if file_access:
			file_access.store_buffer(zip_reader.read_file(file_in_zip))
			file_access.close()
		else:
			log_to_console("Failed to write file: " + full_path + " - Check file permissions or if it's in use.")

	# Recursively search for the executable
	_find_and_execute_exe(extracted_path)

func _find_and_execute_exe(path):
	var dir_access = DirAccess.open(path)
	if dir_access:
		dir_access.list_dir_begin()
		var file_name = dir_access.get_next()
		while file_name != "":
			if file_name.ends_with(".exe"):
				var exec_path = path + "/" + file_name
				OS.shell_show_in_file_manager(exec_path)
				var output = []
				var error_code = OS.execute(exec_path, ["--editor"], output, true, false)
				if error_code == OK:
					log_to_console("Executable is running: " + exec_path)
					for line in output:
						log_to_console(line)
					return true
				else:
					log_to_console("Failed to execute: " + exec_path + " with error code: " + str(error_code))
			elif dir_access.current_is_dir() and file_name != "." and file_name != "..":
				if _find_and_execute_exe(path + "/" + file_name):
					return true
			file_name = dir_access.get_next()
		dir_access.list_dir_end()
	return false

func update_current_and_latest_values():
	var engine_data = Engine.get_version_info()
	current_version_label.text = "Current Version: " + str(engine_data["string"])
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_latest_version_fetched)
	http_request.request(GODOT_RELEASES_URL)
	log_to_console("Fetching latest Godot release...")
		
func _on_latest_version_fetched(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json:
			var latest_release = json
			latest_version_label.text = "Latest Version: " + latest_release["tag_name"]
			log_to_console("Latest Godot version fetched: " + latest_release["tag_name"])
		else:
			log_to_console("Failed to parse latest version data.")
	else:
		log_to_console("Failed to fetch latest version.")

func _on_directory_button_pressed():
	file_dialog.show()

func _on_file_dialog_dir_selected(dir):
	selected_path = dir
	directory_label.text = selected_path 
	log_to_console("Save path updated.")

func _on_file_dialog_confirmed():
	file_dialog.hide() 
	validate_directory()

func log_to_console(message: String):
	console.add_text(message + "\n") 

func _on_check_box_toggled(toggled_on):
	needs_dotnet = toggled_on
