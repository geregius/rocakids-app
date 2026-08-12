import 'package:flutter/material.dart';

/// Placeholder: el registro completo de Acudiente + Niño(s) se construye
/// en el Módulo 3 (CRUD de Niños y Acudientes). Este botón ya existe en
/// el login para que la navegación quede lista desde ya.
class AcudienteProximamenteScreen extends StatelessWidget {
  const AcudienteProximamenteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Acudiente')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'El registro de acudientes y niños estará disponible muy pronto.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
