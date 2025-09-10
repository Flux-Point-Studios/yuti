import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/address_book_service.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';
import '../models/address_book_entry.dart';

class AddressBookScreen extends StatefulWidget {
  final bool isSelectionMode;
  final Function(AddressBookEntry)? onAddressSelected;

  const AddressBookScreen({
    Key? key,
    this.isSelectionMode = false,
    this.onAddressSelected,
  }) : super(key: key);

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  final _addressBookService = AddressBookService();
  final _searchController = TextEditingController();
  
  List<AddressBookEntry> _entries = [];
  List<AddressBookEntry> _filteredEntries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
    });

    await _addressBookService.initialize();
    
    setState(() {
      _entries = _addressBookService.entries;
      _filteredEntries = _entries;
      _isLoading = false;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {
      if (query.isEmpty) {
        _filteredEntries = _entries;
      } else {
        _filteredEntries = _addressBookService.searchByName(query);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.darkGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildEntriesList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: _showAddEntryDialog,
              backgroundColor: AppColors.primaryBlue,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            widget.isSelectionMode ? 'Select Address' : 'Address Book',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (!widget.isSelectionMode)
            IconButton(
              onPressed: _loadEntries,
              icon: Icon(
                Icons.refresh,
                color: AppColors.primaryBlue,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search addresses...',
          hintStyle: TextStyle(color: AppColors.textTertiary),
          prefixIcon: Icon(Icons.search, color: AppColors.primaryBlue),
          filled: true,
          fillColor: AppColors.backgroundLight.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primaryBlue.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primaryBlue.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primaryBlue),
          ),
        ),
        style: TextStyle(color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildEntriesList() {
    if (_filteredEntries.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _filteredEntries.length,
      itemBuilder: (context, index) {
        final entry = _filteredEntries[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildEntryItem(entry),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: GlassmorphismContainer(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.contact_page_outlined,
                size: 64,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                _searchController.text.isNotEmpty 
                    ? 'No matching addresses'
                    : 'No saved addresses',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchController.text.isNotEmpty
                    ? 'Try a different search term'
                    : 'Add addresses to quickly send transactions',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              if (_searchController.text.isEmpty && !widget.isSelectionMode) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _showAddEntryDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Address'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryItem(AddressBookEntry entry) {
    return GestureDetector(
      onTap: widget.isSelectionMode
          ? () => widget.onAddressSelected?.call(entry)
          : () => _showEntryDetails(entry),
      child: GlassmorphismContainer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.person,
                      color: AppColors.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entry.description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            entry.description!,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.isSelectionMode)
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.primaryBlue,
                    )
                  else
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
                      color: AppColors.backgroundDark,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'copy',
                          child: Row(
                            children: [
                              Icon(Icons.copy, color: AppColors.primaryBlue, size: 20),
                              const SizedBox(width: 8),
                              Text('Copy Address', style: TextStyle(color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: AppColors.primaryBlue, size: 20),
                              const SizedBox(width: 8),
                              Text('Edit', style: TextStyle(color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: AppColors.error, size: 20),
                              const SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: AppColors.error)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) => _handleMenuAction(value, entry),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primaryBlue.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.address,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!widget.isSelectionMode) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _copyToClipboard(entry.address),
                        child: Icon(
                          Icons.copy,
                          color: AppColors.primaryBlue,
                          size: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.lastUsed != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Last used: ${_formatDate(entry.lastUsed!)}',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(String action, AddressBookEntry entry) {
    switch (action) {
      case 'copy':
        _copyToClipboard(entry.address);
        break;
      case 'edit':
        _showEditEntryDialog(entry);
        break;
      case 'delete':
        _showDeleteConfirmation(entry);
        break;
    }
  }

  void _showEntryDetails(AddressBookEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              Text(
                entry.name,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              if (entry.handle != null) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Handle', entry.handle!),
              ],

              if (entry.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  entry.description!,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ],
              
              const SizedBox(height: 20),
              
              _buildDetailRow('Address', entry.address, isAddress: true),
              _buildDetailRow('Created', _formatDate(entry.createdAt)),
              if (entry.lastUsed != null)
                _buildDetailRow('Last Used', _formatDate(entry.lastUsed!)),
              
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditEntryDialog(entry);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _copyToClipboard(entry.address),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.backgroundLight.withOpacity(0.2),
                        foregroundColor: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isAddress = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontFamily: isAddress ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddEntryDialog() {
    _showEntryDialog();
  }

  void _showEditEntryDialog(AddressBookEntry entry) {
    _showEntryDialog(entry: entry);
  }

  void _showEntryDialog({AddressBookEntry? entry}) {
    final nameController = TextEditingController(text: entry?.name ?? '');
    final addressController = TextEditingController(text: entry?.address ?? '');
    final handleController = TextEditingController(text: entry?.handle ?? '');
    final descriptionController = TextEditingController(text: entry?.description ?? '');
    final formKey = GlobalKey<FormState>();
    Timer? _handleDebounce;
    String _lastAutoFilledAddress = addressController.text.trim();
    final ValueNotifier<bool> _isResolvingHandle = ValueNotifier<bool>(false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: Text(
          entry == null ? 'Add Address' : 'Edit Address',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundLight.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimary),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: handleController,
                decoration: InputDecoration(
                  labelText: 'ADA Handle (optional, e.g. \$yuti)',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundLight.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: ValueListenableBuilder<bool>(
                    valueListenable: _isResolvingHandle,
                    builder: (context, isLoading, _) {
                      if (!isLoading) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimary),
                onChanged: (value) {
                  // Debounce handle resolution
                  _handleDebounce?.cancel();
                  final trimmed = value.trim();
                  if (trimmed.isEmpty || trimmed.length < 2) {
                    _isResolvingHandle.value = false;
                    return;
                  }
                  _handleDebounce = Timer(const Duration(milliseconds: 600), () async {
                    _isResolvingHandle.value = true;
                    try {
                      final res = await _addressBookService.resolveIfHandle(trimmed);
                      final addr = res['address'];
                      if (addr != null && addr.isNotEmpty && _addressBookService.isValidCardanoAddress(addr)) {
                        final current = addressController.text.trim();
                        if (current.isEmpty || current == _lastAutoFilledAddress) {
                          _lastAutoFilledAddress = addr;
                          addressController.text = addr;
                        }
                      }
                    } catch (_) {}
                    _isResolvingHandle.value = false;
                  });
                },
                onEditingComplete: () async {
                  // Immediate resolve when user finishes editing
                  _handleDebounce?.cancel();
                  final trimmed = handleController.text.trim();
                  if (trimmed.isEmpty) return;
                  _isResolvingHandle.value = true;
                  try {
                    final res = await _addressBookService.resolveIfHandle(trimmed);
                    final addr = res['address'];
                    if (addr != null && addr.isNotEmpty && _addressBookService.isValidCardanoAddress(addr)) {
                      final current = addressController.text.trim();
                      if (current.isEmpty || current == _lastAutoFilledAddress) {
                        _lastAutoFilledAddress = addr;
                        addressController.text = addr;
                      }
                    }
                  } catch (_) {}
                  _isResolvingHandle.value = false;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Address',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundLight.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: IconButton(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        addressController.text = data!.text!;
                      }
                    },
                    icon: Icon(Icons.paste, color: AppColors.primaryBlue),
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                maxLines: 3,
                validator: (value) {
                  if ((value == null || value.trim().isEmpty) && handleController.text.trim().isEmpty) {
                    return 'Enter an address or ADA Handle';
                  }
                  if (value != null && value.trim().isNotEmpty && !_addressBookService.isValidCardanoAddress(value.trim())) {
                    return 'Invalid Cardano address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundLight.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimary),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _handleDebounce?.cancel();
              _isResolvingHandle.value = false;
              Navigator.pop(context);
            },
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                _handleDebounce?.cancel();
                _isResolvingHandle.value = false;
                // Resolve handle if provided and no address entered
                String resolvedAddress = addressController.text.trim();
                String? savedHandle = handleController.text.trim().isEmpty ? null : handleController.text.trim();
                if (resolvedAddress.isEmpty && savedHandle != null) {
                  try {
                    final res = await _addressBookService.resolveIfHandle(savedHandle);
                    resolvedAddress = res['address']!;
                    savedHandle = res['handle'] ?? savedHandle;
                  } catch (_) {}
                }

                if (!_addressBookService.isValidCardanoAddress(resolvedAddress)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Failed to resolve handle to address'), backgroundColor: AppColors.error),
                  );
                  return;
                }

                final newEntry = AddressBookEntry(
                  id: entry?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  address: resolvedAddress,
                  handle: savedHandle,
                  description: descriptionController.text.trim().isEmpty 
                      ? null 
                      : descriptionController.text.trim(),
                  createdAt: entry?.createdAt ?? DateTime.now(),
                  lastUsed: entry?.lastUsed,
                );

                bool success;
                if (entry == null) {
                  success = await _addressBookService.addEntry(newEntry);
                } else {
                  success = await _addressBookService.updateEntry(entry.id, newEntry);
                }

                if (success) {
                  Navigator.pop(context);
                  await _loadEntries();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Name or address already exists'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: Text(entry == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(AddressBookEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: Text(
          'Delete Address',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${entry.name}"? This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await _addressBookService.deleteEntry(entry.id);
              Navigator.pop(context);
              
              if (success) {
                await _loadEntries();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Address deleted'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete address'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address copied to clipboard'),
        backgroundColor: AppColors.primaryBlue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final entryDate = DateTime(date.year, date.month, date.day);

    if (entryDate == today) {
      return 'Today';
    } else if (entryDate == yesterday) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}