import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../theme/app_colors.dart';

const _nombresMeses = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Selector de fecha de nacimiento por día/mes/año (más rápido de llenar
/// que un calendario para fechas de hace varios años, sobre todo el año).
/// Muestra debajo la edad actual y el grupo del ministerio al que
/// pertenecería el niño hoy — ver [grupoParaEdad] para por qué eso nunca
/// se guarda.
class SelectorFechaNacimiento extends StatefulWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const SelectorFechaNacimiento({super.key, required this.value, required this.onChanged});

  @override
  State<SelectorFechaNacimiento> createState() => _SelectorFechaNacimientoState();
}

class _SelectorFechaNacimientoState extends State<SelectorFechaNacimiento> {
  int? _dia;
  int? _mes;
  int? _anio;

  @override
  void initState() {
    super.initState();
    _dia = widget.value?.day;
    _mes = widget.value?.month;
    _anio = widget.value?.year;
  }

  void _actualizar() {
    if (_dia == null || _mes == null || _anio == null) {
      widget.onChanged(null);
      return;
    }
    final diasEnMes = DateUtils.getDaysInMonth(_anio!, _mes!);
    if (_dia! > diasEnMes) _dia = diasEnMes;
    widget.onChanged(DateTime(_anio!, _mes!, _dia!));
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    final anioMin = anioActual - edadMaximaRegistro - 1;
    final anioMax = anioActual - edadMinimaRegistro;
    final diasEnMesActual =
        (_anio != null && _mes != null) ? DateUtils.getDaysInMonth(_anio!, _mes!) : 31;

    final fecha = widget.value;
    final edad = fecha != null ? calcularEdad(fecha) : null;
    final grupo = edad != null ? grupoParaEdad(edad) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fecha de nacimiento', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                key: ValueKey('dia_$diasEnMesActual'),
                initialValue: _dia,
                decoration: const InputDecoration(labelText: 'Día'),
                items: List.generate(
                  diasEnMesActual,
                  (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                ),
                onChanged: (v) => setState(() {
                  _dia = v;
                  _actualizar();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                initialValue: _mes,
                decoration: const InputDecoration(labelText: 'Mes'),
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(value: i + 1, child: Text(_nombresMeses[i])),
                ),
                onChanged: (v) => setState(() {
                  _mes = v;
                  _actualizar();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                initialValue: _anio,
                decoration: const InputDecoration(labelText: 'Año'),
                items: List.generate(
                  anioMax - anioMin + 1,
                  (i) => DropdownMenuItem(value: anioMin + i, child: Text('${anioMin + i}')),
                ),
                onChanged: (v) => setState(() {
                  _anio = v;
                  _actualizar();
                }),
              ),
            ),
          ],
        ),
        if (fecha != null) ...[
          const SizedBox(height: 8),
          Text(
            grupo != null
                ? 'Edad actual: $edad años · Grupo: $grupo'
                : 'Edad actual: $edad años · RocaKids recibe niños de '
                    '$edadMinimaRegistro a $edadMaximaRegistro años.',
            style: TextStyle(
              color: grupo == null ? AppColors.rojo : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
