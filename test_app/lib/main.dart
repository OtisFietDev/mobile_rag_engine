// test_app/lib/main.dart
//
// RAG + LLM Integration Test App
// Uses mobile_rag_engine for RAG and flutter_gemma for on-device LLM

import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'screens/model_setup_screen.dart';
import 'screens/rag_chat_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables from .env file
  await dotenv.load(fileName: 'assets/.env');
  
  // For iOS/macOS, use DynamicLibrary.process() since the Rust library
  // is statically linked via Cargokit's -force_load mechanism.
  // For other platforms, use the default dynamic loading.
  if (Platform.isIOS || Platform.isMacOS) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  } else {
    await RustLib.init();
  }
  
  // Initialize flutter_gemma plugin with HuggingFace token from .env
  final hfToken = dotenv.env['HUGGINGFACE_TOKEN'];
  await FlutterGemma.initialize(
    huggingFaceToken: hfToken,
  );
  
  runApp(const TestApp());
}


class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RAG + LLM Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isModelInstalled = false;
  bool _isChecking = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _checkAndActivateModel();
  }

  Future<void> _checkAndActivateModel() async {
    try {
      // Check if any model is already installed
      final installedModels = await FlutterGemma.listInstalledModels();
      
      if (installedModels.isNotEmpty) {
        setState(() => _statusMessage = 'Activating model...');
        
        // Get the first installed model's file path
        final modelId = installedModels.first;
        final dir = await getApplicationDocumentsDirectory();
        final modelPath = '${dir.path}/$modelId';
        
        // Activate the model from local file
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromFile(modelPath).install();
        
        setState(() {
          _isChecking = false;
          _isModelInstalled = true;
          _statusMessage = null;
        });
      } else {
        setState(() {
          _isChecking = false;
          _isModelInstalled = false;
        });
      }
    } catch (e, stackTrace) {
      // Log detailed error to terminal
      debugPrint('🔴 Model activation error: $e');
      debugPrint('🔴 Stack Trace: $stackTrace');
      
      // If error, assume no model installed - user can reinstall
      setState(() {
        _isChecking = false;
        _isModelInstalled = false;
        _statusMessage = null; // Clear status, show install button
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_statusMessage ?? 'Checking model status...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🤖 RAG + LLM Test'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_documents',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep),
                  title: Text('Clear Documents'),
                  subtitle: Text('Reset RAG database'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete_model',
                child: ListTile(
                  leading: Icon(Icons.delete),
                  title: Text('Delete Model'),
                  subtitle: Text('Remove downloaded model'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'change_model',
                child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('Change Model'),
                  subtitle: Text('Download different model'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isModelInstalled ? Icons.check_circle : Icons.download,
                size: 80,
                color: _isModelInstalled ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 24),
              Text(
                _isModelInstalled
                    ? 'Model Ready!'
                    : 'LLM Model Required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _isModelInstalled
                    ? 'You can start chatting with RAG-powered responses.'
                    : 'Install a Gemma model to enable AI responses.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 32),
              if (!_isModelInstalled)
                FilledButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ModelSetupScreen(),
                      ),
                    );
                    if (result == true) {
                      setState(() => _isModelInstalled = true);
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Install Model'),
                ),
              if (_isModelInstalled)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RagChatScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('Start Chat'),
                ),
              const SizedBox(height: 16),
              // Skip model installation for testing RAG only
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RagChatScreen(mockLlm: true),
                    ),
                  );
                },
                child: const Text('Skip (Test RAG only)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case 'clear_documents':
        await _clearDocuments();
        break;
      case 'delete_model':
        await _deleteModel();
        break;
      case 'change_model':
        await _changeModel();
        break;
    }
  }

  Future<void> _clearDocuments() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Documents?'),
        content: const Text(
          'This will delete all stored documents and RAG data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final dbPath = '${dir.path}/test_rag_chat.db';
        final dbFile = File(dbPath);
        
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Documents cleared successfully')),
          );
        }
      } catch (e) {
        debugPrint('🔴 Error clearing documents: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteModel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model?'),
        content: const Text(
          'This will delete the downloaded LLM model. You will need to download it again to use AI features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final installedModels = await FlutterGemma.listInstalledModels();
        
        for (final modelId in installedModels) {
          await FlutterGemma.uninstallModel(modelId);
          debugPrint('🗑️ Deleted model: $modelId');
        }
        
        setState(() => _isModelInstalled = false);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Model deleted successfully')),
          );
        }
      } catch (e) {
        debugPrint('🔴 Error deleting model: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _changeModel() async {
    // Delete current model first
    await _deleteModel();
    
    // Navigate to model setup screen
    if (mounted && !_isModelInstalled) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const ModelSetupScreen(),
        ),
      );
      if (result == true) {
        setState(() => _isModelInstalled = true);
      }
    }
  }
}
