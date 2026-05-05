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

  // --- ADDED MISSING DECLARATIONS ---
  String _selectedMode = 'Normal'; 
  String _selectedSide = 'Front';

  final TextEditingController _projectController = TextEditingController();
  final String serverIp = "http://104.154.76.47:5001";

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

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

  Future<void> _processImage({required bool isGolden}) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (pickedFile != null) {
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

      try {
        String endpoint = isGolden ? "/upload_golden" : "/inspect";
        var request = http.MultipartRequest('POST', Uri.parse('$serverIp$endpoint'));

        String projName = _projectController.text.trim().replaceAll(" ", "_");
        if (projName.isEmpty) {
          setState(() => _status = "Error: Project Name Required");
          return;
        }

        request.fields['project_name'] = projName;
        request.fields['batch_number'] = _batchNumber;
        request.fields['inspection_type'] = _selectedMode.toLowerCase(); 
        request.fields['selected_side'] = _selectedSide.toLowerCase();

        request.files.add(await http.MultipartFile.fromPath('image', _image!.path));

        var streamedResponse = await request.send().timeout(Duration(seconds: 60));
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          var data = json.decode(response.body);
          setState(() {
            _status = isGolden ? "Golden Saved Successfully!" : data['status'];
            if (!isGolden) {
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
    } // Closes if (pickedFile != null)
  } // Closes _processImage

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
              
              // --- ADDED UI FOR MODE & SIDE SELECTION ---
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedMode,
                      decoration: InputDecoration(labelText: "Mode", border: OutlineInputBorder()),
                      items: ["Normal", "Deep"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) => setState(() => _selectedMode = val!),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedSide,
                      decoration: InputDecoration(labelText: "Side", border: OutlineInputBorder()),
                      items: ["Front", "Back"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) => setState(() => _selectedSide = val!),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),

              TextField(
                decoration: InputDecoration(
                  labelText: "Batch Number", 
                  border: OutlineInputBorder()
                ),
                onChanged: (val) => _batchNumber = val,
              ),
              SizedBox(height: 20),
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
