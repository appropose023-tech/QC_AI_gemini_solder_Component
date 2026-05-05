import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'dart:convert';

void main() => runApp(MaterialApp(
      home: PCBInspectorApp(),
      theme: ThemeData(
        primarySwatch: Colors.indigo, 
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      debugShowCheckedModeBanner: false,
    ));

class PCBInspectorApp extends StatefulWidget {
  @override
  _PCBInspectorAppState createState() => _PCBInspectorAppState();
}

class _PCBInspectorAppState extends State<PCBInspectorApp> {
  File? _image;
  String? _selectedProject;
  List<String> _existingProjects = [];
  String _batchNumber = "B01";
  String _status = "Ready";
  String? _reportUrl;

  final TextEditingController _projectController = TextEditingController();
  // Ensure this IP matches your Google Cloud / Server address
  final String serverIp = "http://104.154.76.47:5001";

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

  // 1. Fetch existing project folders from the server
  Future<void> _fetchProjects() async {
    try {
      final response = await http.get(Uri.parse('$serverIp/get_projects'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _existingProjects = List<String>.from(data['projects']);
        });
      }
    } catch (e) {
      setState(() => _status = "Fetch Error: Check Server Connection");
    }
  }

  // 2. Capture, Crop, and Upload logic
  Future<void> _processImage({required bool isGolden}) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90, // High quality for YOLO detection
    );

    if (pickedFile != null) {
      // IMAGE CROPPER (Updated for version 12.1.0+)
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: isGolden ? 'Align Golden Sample' : 'Align Test PCB',
            toolbarColor: isGolden ? Colors.orange[800] : Colors.indigo,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: isGolden ? 'Align Golden Sample' : 'Align Test PCB',
          ),
        ],
      );

      if (croppedFile == null) return;

      setState(() {
        _image = File(croppedFile.path);
        _status = isGolden ? "Uploading Master..." : "Analyzing...";
        _reportUrl = null;
      });

     // UPLOAD LOGIC
try {
  String endpoint = isGolden ? "/upload_golden" : "/inspect";
  var request = http.MultipartRequest('POST', Uri.parse('$serverIp$endpoint'));

  // 1. Project Name from TextField
  String projName = _projectController.text.trim().replaceAll(" ", "_");
  if (projName.isEmpty) {
    setState(() => _status = "Error: Project Name Required");
    return;
  }

  request.fields['project_name'] = projName;
  request.fields['batch_number'] = _batchNumber;

  // --- NEW FIELDS FOR DUAL-MODE INSPECTION ---
  // Convert to lowercase to match Python's .lower() expectations
  request.fields['inspection_type'] = _selectedMode.toLowerCase(); 
  request.fields['selected_side'] = _selectedSide.toLowerCase();
  // -------------------------------------------

  request.files.add(await http.MultipartFile.fromPath('image', _image!.path));

  // Set timeout to 60s as deep inspection (YOLO x2 + Alignment) takes longer
  var streamedResponse = await request.send().timeout(Duration(seconds: 60));
  var response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode == 200) {
    var data = json.decode(response.body);
    setState(() {
      // Backend now returns specific status like "Different PCB Detected" or "Success"
      _status = isGolden ? "Golden Saved Successfully!" : data['status'];
      
      if (!isGolden) {
        // Timestamp forces Flutter to reload the image from the server even if URL is same
        _reportUrl = serverIp + data['report_url'] + "?t=${DateTime.now().millisecondsSinceEpoch}";
      }
    });
    
    if (isGolden) _fetchProjects();
  } else {
    setState(() => _status = "Server Error: ${response.statusCode}");
  }
} catch (e) {
  setState(() => _status = "Connection Failed: $e");
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("QC AI - PCB Inspector"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PROJECT INPUT
              TextField(
                controller: _projectController,
                decoration: InputDecoration(
                  labelText: "Current Project Name",
                  hintText: "Enter name (e.g., Inverter_V1)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.precision_manufacturing),
                ),
              ),
              SizedBox(height: 12),

              // DYNAMIC PROJECT DROPDOWN
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Quick Select Existing Project",
                ),
                value: _existingProjects.contains(_selectedProject) ? _selectedProject : null,
                items: _existingProjects.map((String val) {
                  return DropdownMenuItem<String>(value: val, child: Text(val));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedProject = val;
                    _projectController.text = val!;
                  });
                },
              ),
              SizedBox(height: 12),

              // BATCH NUMBER
              TextField(
                decoration: InputDecoration(
                  labelText: "Batch Number", 
                  border: OutlineInputBorder()
                ),
                onChanged: (val) => _batchNumber = val,
              ),
              SizedBox(height: 20),

              // ACTION BUTTONS
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _processImage(isGolden: true),
                      icon: Icon(Icons.stars),
                      label: Text("Set Golden"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[800], 
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12)
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _processImage(isGolden: false),
                      icon: Icon(Icons.camera_alt),
                      label: Text("Inspect"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo, 
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12)
                      ),
                    ),
                  ),
                ],
              ),

              Divider(height: 40, thickness: 1),

              // STATUS DISPLAY
              Center(
                child: Text(
                  "Status: $_status",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _status.contains("Defect") || _status.contains("Error") 
                        ? Colors.red 
                        : Colors.green[700],
                  ),
                ),
              ),

              // RESULTS DISPLAY
              if (_reportUrl != null) ...[
                SizedBox(height: 20),
                Text("Inspection Report (AI Analysis):", 
                  style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _reportUrl!, 
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(child: CircularProgressIndicator());
                    },
                  ),
                ),
              ] else if (_image != null) ...[
                SizedBox(height: 20),
                Text("Last Captured Image (Local):"),
                SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_image!, height: 250, fit: BoxFit.cover),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
