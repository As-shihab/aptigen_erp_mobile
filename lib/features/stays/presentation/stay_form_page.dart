import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/media_library_dialog.dart';
import '../data/stays_service.dart';
import '../models/stay_model.dart';

const _propertyTypes = [
  {'id': 'house', 'label': 'House', 'emoji': '🏠'},
  {'id': 'apartment', 'label': 'Apartment', 'emoji': '🏢'},
  {'id': 'villa', 'label': 'Villa', 'emoji': '🏡'},
  {'id': 'cabin', 'label': 'Cabin', 'emoji': '🪵'},
  {'id': 'beach', 'label': 'Beach house', 'emoji': '🏖️'},
  {'id': 'farm', 'label': 'Farm', 'emoji': '🌾'},
  {'id': 'boat', 'label': 'Boat', 'emoji': '⛵'},
  {'id': 'treehouse', 'label': 'Treehouse', 'emoji': '🌳'},
];

/// Create/edit a `stays` listing — a single scrollable form mirroring
/// erp/desktop's CreateStays.tsx step-wizard fields, flattened for mobile
/// (matches this app's NoteEditorPage single-page editor convention rather
/// than porting the desktop wizard's step animation).
class StayFormPage extends StatefulWidget {
  final Stay? existing;
  const StayFormPage({super.key, this.existing});

  @override
  State<StayFormPage> createState() => _StayFormPageState();
}

class _StayFormPageState extends State<StayFormPage> {
  final _service = StaysService(ApiClient());

  bool get _isEdit => widget.existing != null;

  late String _propertyType = widget.existing?.propertyType ?? '';
  late int? _categoryId = widget.existing?.categoryId;
  late final _addressController = TextEditingController(text: widget.existing?.address ?? '');
  late final _cityController = TextEditingController(text: widget.existing?.city ?? '');
  late final _countryController = TextEditingController(text: widget.existing?.country ?? '');
  late int _maxGuests = widget.existing?.maxGuests ?? 2;
  late int _bedroomCount = widget.existing?.bedroomCount ?? 1;
  late int _bedCount = widget.existing?.bedCount ?? 1;
  late double _bathroomCount = widget.existing?.bathroomCount ?? 1;
  late final Set<int> _amenityIds = {...(widget.existing?.amenityIds ?? [])};
  late List<StayMedia> _media = [...(widget.existing?.medias ?? [])];
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _descriptionController = TextEditingController(text: widget.existing?.description ?? '');
  late final _priceController = TextEditingController(
    text: widget.existing?.pricePerNight != null ? widget.existing!.pricePerNight!.toStringAsFixed(0) : '',
  );
  late final _cleaningFeeController = TextEditingController(
    text: widget.existing != null && widget.existing!.cleaningFee > 0 ? widget.existing!.cleaningFee.toStringAsFixed(0) : '',
  );

  bool _amenitiesLoading = true;
  bool _categoriesLoading = true;
  List<StayAmenity> _amenities = [];
  List<StayCategory> _categories = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadAmenities();
    _loadCategories();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _cleaningFeeController.dispose();
    super.dispose();
  }

  Future<void> _loadAmenities() async {
    try {
      final result = await _service.loadAmenities();
      if (!mounted) return;
      setState(() => _amenities = result);
    } catch (_) {
      // leave empty — form still usable without amenities
    } finally {
      if (mounted) setState(() => _amenitiesLoading = false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final result = await _service.loadCategories();
      if (!mounted) return;
      setState(() => _categories = result);
    } catch (_) {
      // leave empty — form still usable without categories
    } finally {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  void _toggleAmenity(int id) {
    setState(() {
      if (_amenityIds.contains(id)) {
        _amenityIds.remove(id);
      } else {
        _amenityIds.add(id);
      }
    });
  }

  Future<void> _pickMedia() async {
    final picked = await showMediaLibraryDialog(context, title: 'Select Photos', multiSelect: true, defaultCategoryName: 'Stays');
    if (picked == null || picked.isEmpty) return;
    final existingUrls = _media.map((m) => m.url).toSet();
    final toAdd = picked.where((item) => !existingUrls.contains(item.fileUrl)).map((item) => StayMedia(
          url: item.fileUrl,
          type: item.isImage ? 'image' : 'video',
          name: item.name,
          position: 0,
        ));
    setState(() {
      _media = [..._media, ...toAdd];
      for (var i = 0; i < _media.length; i++) {
        _media[i] = StayMedia(url: _media[i].url, type: _media[i].type, name: _media[i].name, position: i);
      }
    });
  }

  void _removeMedia(String url) {
    setState(() {
      _media = _media.where((m) => m.url != url).toList();
      for (var i = 0; i < _media.length; i++) {
        _media[i] = StayMedia(url: _media[i].url, type: _media[i].type, name: _media[i].name, position: i);
      }
    });
  }

  Future<void> _submit(String status) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a title.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final payload = {
        'title': title,
        'description': _descriptionController.text.trim(),
        'property_type': _propertyType.isEmpty ? null : _propertyType,
        'category_id': _categoryId,
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'country': _countryController.text.trim(),
        'max_guests': _maxGuests,
        'bedroom_count': _bedroomCount,
        'bed_count': _bedCount,
        'bathroom_count': _bathroomCount,
        'price_per_night': _priceController.text.trim().isEmpty ? null : double.tryParse(_priceController.text.trim()),
        'cleaning_fee': _cleaningFeeController.text.trim().isEmpty ? 0 : double.tryParse(_cleaningFeeController.text.trim()) ?? 0,
        'amenity_ids': _amenityIds.toList(),
        'media': _media.map((m) => m.toJson()).toList(),
        'status': status,
      };
      if (_isEdit) {
        await _service.update(widget.existing!.id, payload);
      } else {
        await _service.create(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this stay.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Stay' : 'New Stay'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => _submit('draft'),
            child: Text(_isEdit ? 'Save' : 'Save draft'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _sectionLabel('Property type'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _propertyTypes.map((t) {
              final selected = _propertyType == t['id'];
              return ChoiceChip(
                label: Text('${t['emoji']}  ${t['label']}'),
                selected: selected,
                onSelected: (_) => setState(() => _propertyType = t['id']!),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),
          _sectionLabel('Category'),
          if (_categoriesLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
          else if (_categories.isEmpty)
            Text('No categories configured.', style: TextStyle(color: AppColors.slate600, fontSize: 12))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) {
                final selected = _categoryId == c.id;
                return ChoiceChip(
                  label: Text(c.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _categoryId = selected ? null : c.id),
                );
              }).toList(),
            ),

          const SizedBox(height: 20),
          _sectionLabel('Location'),
          TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Street address', prefixIcon: Icon(Icons.location_on_outlined))),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: TextField(controller: _cityController, decoration: const InputDecoration(labelText: 'City'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _countryController, decoration: const InputDecoration(labelText: 'Country'))),
            ],
          ),

          const SizedBox(height: 20),
          _sectionLabel('Basics'),
          _counterRow('Guests', _maxGuests.toDouble(), (v) => setState(() => _maxGuests = v.round()), min: 1),
          _counterRow('Bedrooms', _bedroomCount.toDouble(), (v) => setState(() => _bedroomCount = v.round()), min: 1),
          _counterRow('Beds', _bedCount.toDouble(), (v) => setState(() => _bedCount = v.round()), min: 1),
          _counterRow('Bathrooms', _bathroomCount, (v) => setState(() => _bathroomCount = v), min: 0.5, step: 0.5),

          const SizedBox(height: 20),
          _sectionLabel('Amenities'),
          if (_amenitiesLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
          else if (_amenities.isEmpty)
            Text('No amenities configured.', style: TextStyle(color: AppColors.slate600, fontSize: 12))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _amenities.map((a) {
                final selected = _amenityIds.contains(a.id);
                return FilterChip(
                  label: Text(a.label),
                  selected: selected,
                  onSelected: (_) => _toggleAmenity(a.id),
                );
              }).toList(),
            ),

          const SizedBox(height: 20),
          _sectionLabel('Photos'),
          OutlinedButton.icon(onPressed: _pickMedia, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Choose from media library')),
          if (_media.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _media.map((m) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: m.type == 'video'
                          ? Container(width: 72, height: 72, color: AppColors.slate100, child: const Icon(Icons.videocam_outlined))
                          : Image.network(m.url, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => _removeMedia(m.url),
                        child: const CircleAvatar(radius: 9, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 11, color: Colors.white)),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 20),
          _sectionLabel('Title & description'),
          TextField(controller: _titleController, maxLength: 50, decoration: const InputDecoration(labelText: 'Title')),
          TextField(controller: _descriptionController, maxLines: 5, minLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true)),

          const SizedBox(height: 8),
          _sectionLabel('Price'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Price per night', prefixText: '${currencySymbol()} '),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cleaningFeeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Cleaning fee', prefixText: '${currencySymbol()} '),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _submitting ? null : () => _submit('active'),
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save & publish' : 'Publish listing'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _counterRow(String label, double value, ValueChanged<double> onChanged, {double min = 1, double step = 1}) {
    final display = value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => onChanged((value - step).clamp(min, double.infinity)),
              ),
              SizedBox(width: 28, child: Text(display, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => onChanged(value + step),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
