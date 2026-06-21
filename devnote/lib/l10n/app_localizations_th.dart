// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'บันทึก';

  @override
  String get editor => 'ตัวแก้ไข';

  @override
  String get search => 'ค้นหา';

  @override
  String get settings => 'การตั้งค่า';

  @override
  String get knowledgeGraph => 'กราฟความรู้';

  @override
  String get noteList => 'รายการบันทึก';

  @override
  String get editNote => 'แก้ไขบันทึก';

  @override
  String get newNote => 'บันทึกใหม่';

  @override
  String get untitled => 'ไม่มีชื่อ';

  @override
  String get noContent => 'ไม่มีเนื้อหา';

  @override
  String get noNotes => 'ยังไม่มีบันทึก';

  @override
  String get noFolders => 'ยังไม่มีโฟลเดอร์';

  @override
  String get newFolder => 'โฟลเดอร์ใหม่';

  @override
  String get newSubFolder => 'โฟลเดอร์ย่อยใหม่';

  @override
  String get folderName => 'ชื่อโฟลเดอร์';

  @override
  String get create => 'สร้าง';

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get confirm => 'ยืนยัน';

  @override
  String get delete => 'ลบ';

  @override
  String get rename => 'เปลี่ยนชื่อ';

  @override
  String get renameFolder => 'เปลี่ยนชื่อโฟลเดอร์';

  @override
  String get ok => 'ตกลง';

  @override
  String get save => 'บันทึก';

  @override
  String get open => 'เปิด';

  @override
  String get expand => 'ขยาย';

  @override
  String get darkMode => 'โหมดมืด';

  @override
  String get darkModeSubtitle => 'สลับธีมมืด/สว่าง';

  @override
  String get fontSize => 'ขนาดตัวอักษร';

  @override
  String get autoSave => 'บันทึกอัตโนมัติ';

  @override
  String get autoSaveSubtitle => 'บันทึกบันทึกอัตโนมัติขณะแก้ไข';

  @override
  String get defaultEditMode => 'โหมดแก้ไขเริ่มต้น';

  @override
  String get richText => 'ข้อความจัดรูปแบบ';

  @override
  String get syncSettings => 'การตั้งค่าการซิงค์';

  @override
  String get syncSettingsSubtitle => 'กำหนดค่าการซิงค์ข้อมูลและการแก้ไขความขัดแย้ง';

  @override
  String get cryptoSettings => 'การตั้งค่าการเข้ารหัส';

  @override
  String get cryptoSettingsSubtitle => 'จัดการการเข้ารหัสบันทึกและรหัสผ่าน';

  @override
  String get p2pSync => 'การซิงค์ P2P';

  @override
  String get p2pSyncSubtitle => 'ซิงค์ข้อมูลระหว่างอุปกรณ์โดยตรง';

  @override
  String get pluginMarketplace => 'ตลาดปลั๊กอิน';

  @override
  String get pluginMarketplaceSubtitle => 'เรียกดูและติดตั้งปลั๊กอิน';

  @override
  String get pluginManagement => 'จัดการปลั๊กอิน';

  @override
  String get pluginManagementSubtitle => 'จัดการปลั๊กอินที่ติดตั้งแล้ว';

  @override
  String get importExport => 'นำเข้า/ส่งออก';

  @override
  String get importExportSubtitle => 'นำเข้าหรือส่งออกข้อมูลบันทึก';

  @override
  String get dataBackup => 'สำรองข้อมูล';

  @override
  String get dataBackupSubtitle => 'ส่งออกข้อมูลบันทึก';

  @override
  String get clearCache => 'ล้างแคช';

  @override
  String get clearCacheSubtitle => 'ล้างข้อมูลแคชในเครื่อง';

  @override
  String get version => 'เวอร์ชัน';

  @override
  String get openSourceLicenses => 'ลิขสิทธิ์โอเพนซอร์ส';

  @override
  String get appearance => 'ลักษณะ';

  @override
  String get data => 'ข้อมูล';

  @override
  String get about => 'เกี่ยวกับ';

  @override
  String get gridView => 'มุมมองตาราง';

  @override
  String get listView => 'มุมมองรายการ';

  @override
  String get sort => 'เรียงลำดับ';

  @override
  String get sortByUpdatedAt => 'ตามเวลาที่แก้ไข';

  @override
  String get sortByCreatedAt => 'ตามเวลาที่สร้าง';

  @override
  String get sortByTitle => 'ตามชื่อเรื่อง';

  @override
  String get paragraph => 'ย่อหน้า';

  @override
  String get heading => 'หัวข้อ';

  @override
  String get codeBlock => 'บล็อกโค้ด';

  @override
  String get bulletList => 'รายการจุดนำ';

  @override
  String get quote => 'อ้างอิง';

  @override
  String get noteType => 'บันทึก';

  @override
  String get tagType => 'แท็ก';

  @override
  String get folderType => 'โฟลเดอร์';

  @override
  String get canvasType => 'ผ้าใบ';

  @override
  String get centralityAnalysis => 'การวิเคราะห์ความเป็นศูนย์กลาง';

  @override
  String get clusterDetection => 'การตรวจจับคลัสเตอร์';

  @override
  String get enableEncryption => 'เปิดใช้งานการเข้ารหัส';

  @override
  String get disableEncryption => 'ปิดใช้งานการเข้ารหัส';

  @override
  String get lock => 'ล็อก';

  @override
  String get unlock => 'ปลดล็อก';

  @override
  String get changePassword => 'เปลี่ยนรหัสผ่าน';

  @override
  String get setEncryptionPassword => 'ตั้งรหัสผ่านการเข้ารหัส';

  @override
  String get verifyPassword => 'ยืนยันรหัสผ่าน';

  @override
  String get enterCurrentPassword => 'ป้อนรหัสผ่านปัจจุบัน';

  @override
  String get setNewPassword => 'ตั้งรหัสผ่านใหม่';

  @override
  String get enterPasswordToUnlock => 'ป้อนรหัสผ่านเพื่อปลดล็อก';

  @override
  String get encryptionEnabled => 'เปิดใช้งานการเข้ารหัสแล้ว';

  @override
  String get encryptionDisabled => 'ปิดใช้งานการเข้ารหัสแล้ว';

  @override
  String get passwordChanged => 'เปลี่ยนรหัสผ่านแล้ว';

  @override
  String get wrongPassword => 'รหัสผ่านผิด';

  @override
  String get enableEncryptionFailed => 'เปิดใช้งานการเข้ารหัสไม่สำเร็จ รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';

  @override
  String get wrongPasswordCannotDisable => 'รหัสผ่านผิด ไม่สามารถปิดใช้งานการเข้ารหัสได้';

  @override
  String get passwordChangeFailed => 'เปลี่ยนรหัสผ่านไม่สำเร็จ โปรดตรวจสอบรหัสผ่านปัจจุบัน';

  @override
  String get encryptionControl => 'การควบคุมการเข้ารหัส';

  @override
  String get encryptionAlgorithm => 'อัลกอริทึมการเข้ารหัส';

  @override
  String get standard => 'มาตรฐาน';

  @override
  String get standardSubtitle => 'Argon2id 3 รอบ เหมาะสำหรับการใช้งานประจำวัน';

  @override
  String get highStrength => 'ความปลอดภัยสูง';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 รอบ ความปลอดภัยสูงขึ้น';

  @override
  String get encryptionInstructions => 'คำแนะนำการเข้ารหัส';

  @override
  String get encryptionDescription => '• หลังเปิดใช้งานการเข้ารหัส เนื้อหาบันทึกจะถูกเข้ารหัสด้วย XChaCha20-Poly1305\n• รหัสผ่านใช้อัลกอริทึม Argon2id เพื่อสืบค้นกุญแจ\n• โปรดเก็บรหัสผ่านให้ปลอดภัย การสูญเสียรหัสผ่านหมายถึงการสูญเสียข้อมูล\n• หากต้องการเปลี่ยนความแข็งแกร่งของการเข้ารหัส ต้องปิดและเปิดใช้งานใหม่';

  @override
  String get import => 'นำเข้า';

  @override
  String get export => 'ส่งออก';

  @override
  String get markdownFolder => 'โฟลเดอร์ Markdown';

  @override
  String get obsidianVault => 'คลัง Obsidian';

  @override
  String get joplinExport => 'ส่งออก Joplin';

  @override
  String get conflictResolution => 'การแก้ไขความขัดแย้ง';

  @override
  String get skip => 'ข้าม';

  @override
  String get overwrite => 'เขียนทับ';

  @override
  String get startImport => 'เริ่มนำเข้า';

  @override
  String get startExport => 'เริ่มส่งออก';

  @override
  String get allNotes => 'บันทึกทั้งหมด';

  @override
  String get specifiedFolder => 'โฟลเดอร์ที่กำหนด';

  @override
  String get specifiedTag => 'แท็กที่กำหนด';

  @override
  String get conflictHandling => 'การจัดการความขัดแย้ง';

  @override
  String get conflictResolutionTitle => 'การแก้ไขความขัดแย้ง';

  @override
  String get noConflicts => 'ไม่มีความขัดแย้งให้แก้ไข';

  @override
  String get allConflictsResolved => 'แก้ไขความขัดแย้งทั้งหมดแล้ว';

  @override
  String get keepLocalVersion => 'เก็บเวอร์ชันในเครื่องทั้งหมด';

  @override
  String get keepRemoteVersion => 'เก็บเวอร์ชันระยะไกลทั้งหมด';

  @override
  String get conflict => 'ความขัดแย้ง';

  @override
  String get contentConflict => 'ความขัดแย้งของเนื้อหา';

  @override
  String get moveConflict => 'ความขัดแย้งของการย้าย';

  @override
  String get deleteModifyConflict => 'ความขัดแย้งลบ/แก้ไข';

  @override
  String get diffComparison => 'เปรียบเทียบความแตกต่าง';

  @override
  String get localVersion => 'เวอร์ชันในเครื่อง';

  @override
  String get remoteVersion => 'เวอร์ชันระยะไกล';

  @override
  String get quickActions => 'การดำเนินการด่วน';

  @override
  String get keepLocal => 'เก็บในเครื่อง';

  @override
  String get keepRemote => 'เก็บระยะไกล';

  @override
  String get customMerge => 'ผสานแบบกำหนดเอง';

  @override
  String get noContentDifference => 'ไม่มีความแตกต่างของเนื้อหา';

  @override
  String get blockDifferences => 'บล็อกที่แตกต่าง';

  @override
  String get unresolvedBlocks => 'มีบล็อกความแตกต่างที่ยังไม่ได้แก้ไข';

  @override
  String get resolve => 'แก้ไข';

  @override
  String get local => 'ในเครื่อง';

  @override
  String get remote => 'ระยะไกล';

  @override
  String get empty => '(ว่าง)';

  @override
  String get error => 'ข้อผิดพลาด';
}
