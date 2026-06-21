// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Notas';

  @override
  String get editor => 'Editor';

  @override
  String get search => 'Buscar';

  @override
  String get settings => 'Ajustes';

  @override
  String get knowledgeGraph => 'Grafo de conocimiento';

  @override
  String get noteList => 'Lista de notas';

  @override
  String get editNote => 'Editar nota';

  @override
  String get newNote => 'Nueva nota';

  @override
  String get untitled => 'Sin título';

  @override
  String get noContent => 'Sin contenido';

  @override
  String get noNotes => 'Aún no hay notas';

  @override
  String get noFolders => 'Aún no hay carpetas';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get newSubFolder => 'Nueva subcarpeta';

  @override
  String get folderName => 'Nombre de la carpeta';

  @override
  String get create => 'Crear';

  @override
  String get cancel => 'Cancelar';

  @override
  String get confirm => 'Confirmar';

  @override
  String get delete => 'Eliminar';

  @override
  String get rename => 'Renombrar';

  @override
  String get renameFolder => 'Renombrar carpeta';

  @override
  String get ok => 'Aceptar';

  @override
  String get save => 'Guardar';

  @override
  String get open => 'Abrir';

  @override
  String get expand => 'Expandir';

  @override
  String get darkMode => 'Modo oscuro';

  @override
  String get darkModeSubtitle => 'Alternar tema oscuro/claro';

  @override
  String get fontSize => 'Tamaño de fuente';

  @override
  String get autoSave => 'Guardado automático';

  @override
  String get autoSaveSubtitle => 'Guardar notas automáticamente al editar';

  @override
  String get defaultEditMode => 'Modo de edición predeterminado';

  @override
  String get richText => 'Texto enriquecido';

  @override
  String get syncSettings => 'Ajustes de sincronización';

  @override
  String get syncSettingsSubtitle => 'Configurar sincronización de datos y resolución de conflictos';

  @override
  String get cryptoSettings => 'Ajustes de cifrado';

  @override
  String get cryptoSettingsSubtitle => 'Gestionar cifrado de notas y contraseña';

  @override
  String get p2pSync => 'Sincronización P2P';

  @override
  String get p2pSyncSubtitle => 'Sincronizar datos directamente entre dispositivos';

  @override
  String get pluginMarketplace => 'Tienda de plugins';

  @override
  String get pluginMarketplaceSubtitle => 'Explorar e instalar plugins';

  @override
  String get pluginManagement => 'Gestión de plugins';

  @override
  String get pluginManagementSubtitle => 'Gestionar plugins instalados';

  @override
  String get importExport => 'Importar/Exportar';

  @override
  String get importExportSubtitle => 'Importar o exportar datos de notas';

  @override
  String get dataBackup => 'Copia de seguridad';

  @override
  String get dataBackupSubtitle => 'Exportar datos de notas';

  @override
  String get clearCache => 'Borrar caché';

  @override
  String get clearCacheSubtitle => 'Borrar datos almacenados en caché local';

  @override
  String get version => 'Versión';

  @override
  String get openSourceLicenses => 'Licencias de código abierto';

  @override
  String get appearance => 'Apariencia';

  @override
  String get data => 'Datos';

  @override
  String get about => 'Acerca de';

  @override
  String get gridView => 'Vista de cuadrícula';

  @override
  String get listView => 'Vista de lista';

  @override
  String get sort => 'Ordenar';

  @override
  String get sortByUpdatedAt => 'Por fecha de modificación';

  @override
  String get sortByCreatedAt => 'Por fecha de creación';

  @override
  String get sortByTitle => 'Por título';

  @override
  String get paragraph => 'Párrafo';

  @override
  String get heading => 'Encabezado';

  @override
  String get codeBlock => 'Bloque de código';

  @override
  String get bulletList => 'Lista de viñetas';

  @override
  String get quote => 'Cita';

  @override
  String get noteType => 'Nota';

  @override
  String get tagType => 'Etiqueta';

  @override
  String get folderType => 'Carpeta';

  @override
  String get canvasType => 'Lienzo';

  @override
  String get centralityAnalysis => 'Análisis de centralidad';

  @override
  String get clusterDetection => 'Detección de clústeres';

  @override
  String get enableEncryption => 'Activar cifrado';

  @override
  String get disableEncryption => 'Desactivar cifrado';

  @override
  String get lock => 'Bloquear';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get changePassword => 'Cambiar contraseña';

  @override
  String get setEncryptionPassword => 'Establecer contraseña de cifrado';

  @override
  String get verifyPassword => 'Verificar contraseña';

  @override
  String get enterCurrentPassword => 'Introducir contraseña actual';

  @override
  String get setNewPassword => 'Establecer nueva contraseña';

  @override
  String get enterPasswordToUnlock => 'Introducir contraseña para desbloquear';

  @override
  String get encryptionEnabled => 'Cifrado activado';

  @override
  String get encryptionDisabled => 'Cifrado desactivado';

  @override
  String get passwordChanged => 'Contraseña cambiada';

  @override
  String get wrongPassword => 'Contraseña incorrecta';

  @override
  String get enableEncryptionFailed => 'Error al activar el cifrado, la contraseña debe tener al menos 6 caracteres';

  @override
  String get wrongPasswordCannotDisable => 'Contraseña incorrecta, no se puede desactivar el cifrado';

  @override
  String get passwordChangeFailed => 'Error al cambiar la contraseña, compruebe su contraseña actual';

  @override
  String get encryptionControl => 'Control de cifrado';

  @override
  String get encryptionAlgorithm => 'Algoritmo de cifrado';

  @override
  String get standard => 'Estándar';

  @override
  String get standardSubtitle => 'Argon2id 3 iteraciones, adecuado para uso diario';

  @override
  String get highStrength => 'Alta seguridad';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 iteraciones, mayor seguridad';

  @override
  String get encryptionInstructions => 'Instrucciones de cifrado';

  @override
  String get encryptionDescription => '• Al activar el cifrado, el contenido de las notas se cifrará con XChaCha20-Poly1305\n• La contraseña deriva la clave con el algoritmo Argon2id\n• Guarde su contraseña de forma segura, perderla significa perder los datos\n• Para cambiar la fuerza del cifrado, debe desactivarlo y volver a activarlo';

  @override
  String get import => 'Importar';

  @override
  String get export => 'Exportar';

  @override
  String get markdownFolder => 'Carpeta Markdown';

  @override
  String get obsidianVault => 'Caja fuerte de Obsidian';

  @override
  String get joplinExport => 'Exportación de Joplin';

  @override
  String get conflictResolution => 'Resolución de conflictos';

  @override
  String get skip => 'Omitir';

  @override
  String get overwrite => 'Sobrescribir';

  @override
  String get startImport => 'Iniciar importación';

  @override
  String get startExport => 'Iniciar exportación';

  @override
  String get allNotes => 'Todas las notas';

  @override
  String get specifiedFolder => 'Carpeta especificada';

  @override
  String get specifiedTag => 'Etiqueta especificada';

  @override
  String get conflictHandling => 'Gestión de conflictos';

  @override
  String get conflictResolutionTitle => 'Resolución de conflictos';

  @override
  String get noConflicts => 'No hay conflictos que resolver';

  @override
  String get allConflictsResolved => 'Todos los conflictos resueltos';

  @override
  String get keepLocalVersion => 'Mantener todas las versiones locales';

  @override
  String get keepRemoteVersion => 'Mantener todas las versiones remotas';

  @override
  String get conflict => 'Conflicto';

  @override
  String get contentConflict => 'Conflicto de contenido';

  @override
  String get moveConflict => 'Conflicto de movimiento';

  @override
  String get deleteModifyConflict => 'Conflicto de eliminación/modificación';

  @override
  String get diffComparison => 'Comparación de diferencias';

  @override
  String get localVersion => 'Versión local';

  @override
  String get remoteVersion => 'Versión remota';

  @override
  String get quickActions => 'Acciones rápidas';

  @override
  String get keepLocal => 'Mantener local';

  @override
  String get keepRemote => 'Mantener remota';

  @override
  String get customMerge => 'Fusión personalizada';

  @override
  String get noContentDifference => 'Sin diferencia de contenido';

  @override
  String get blockDifferences => 'bloques de diferencia';

  @override
  String get unresolvedBlocks => 'Hay bloques de diferencia sin resolver';

  @override
  String get resolve => 'Resolver';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Remoto';

  @override
  String get empty => '(vacío)';

  @override
  String get error => 'Error';
}
