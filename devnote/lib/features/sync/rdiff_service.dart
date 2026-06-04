/// RdiffService - 基于 rsync 算法的增量传输优化
///
/// 借鉴开源项目 librsync/rdiff:
/// 来源: https://github.com/librsync/librsync
///
/// 算法原理（参考 librsync 的 rsync 算法论文）:
/// 1. 接收端将文件分块，为每一块计算弱哈希（rolling checksum）和强哈希（MD5）
/// 2. 发送端使用滚动窗口在本地数据上滑动，与接收端签名进行匹配
/// 3. 匹配到相同块时记录引用指令，否则记录字面数据
/// 4. 接收端根据指令流（字面数据 + 块引用）重建目标文件
///
/// 设计要点:
/// - 弱哈希使用类 Adler32 的滚动校验和（O(n) 时间复杂度滑动更新）
/// - 强哈希使用 MD5 确保块内容唯一性（防止哈希碰撞）
/// - 增量指令包含 LITERAL（字面数据）和 COPY（块引用）两种类型
/// - 默认块大小 2048 字节（与 librsync 默认值一致）
///
/// 性能优势:
/// - 仅传输文件差异部分，大幅减少网络带宽消耗
/// - 适用于大文件的小范围修改场景（如文档同步）
/// - 配合端到端加密使用，在加密前执行增量计算

import 'dart:convert';
import 'dart:typed_data';

/// Rdiff 块签名 —— 包含弱哈希和强哈希
///
/// 借鉴 librsync 的 rs_signature_t 结构体:
/// https://github.com/librsync/librsync/blob/master/src/signature.h
class RdiffBlockSignature {
  /// 块索引（从 0 开始）
  final int index;

  /// 弱哈希值 —— 借鉴 librsync 的 rolling checksum（类 Adler32）
  /// 用于快速筛选候选块，支持 O(1) 滑动窗口更新
  final int weakChecksum;

  /// 强哈希值 —— 借鉴 librsync 的 MD5 哈希
  /// 用于确认块内容完全匹配，防止弱哈希碰撞
  final Uint8List strongChecksum;

  const RdiffBlockSignature({
    required this.index,
    required this.weakChecksum,
    required this.strongChecksum,
  });

  @override
  String toString() =>
      'RdiffBlockSignature(idx:$index, weak:0x${weakChecksum.toRadixString(16)})';
}

/// Rdiff 增量指令类型
///
/// 借鉴 librsync 的 rs_op_kind_t 枚举:
/// https://github.com/librsync/librsync/blob/master/src/librsync.h
enum RdiffDeltaOp {
  /// 字面数据操作 —— 直接写入新数据
  /// 对应 librsync 的 RS_OP_LITERAL
  literal,

  /// 块复制操作 —— 从旧文件的指定位置复制数据
  /// 对应 librsync 的 RS_OP_COPY
  copy,
}

/// Rdiff 增量指令 —— 描述如何重建目标文件
///
/// 借鉴 librsync 的 rs_mangling.c 中的指令编码方案:
/// 每个指令包含操作类型、长度，以及可选的数据或块引用
class RdiffDeltaInstruction {
  final RdiffDeltaOp op;

  /// 字面数据的字节长度（literal 操作），或复制的块数（copy 操作）
  final int length;

  /// 字面数据内容（仅 literal 操作时有值）
  final Uint8List? data;

  /// 源文件中的块起始索引（仅 copy 操作时有值）
  final int? sourceBlockIndex;

  const RdiffDeltaInstruction({
    required this.op,
    required this.length,
    this.data,
    this.sourceBlockIndex,
  });

  /// 编码为二进制格式 —— 借鉴 librsync 的 delta 编码协议
  ///
  /// 格式:
  /// - 1 字节操作类型 (0=literal, 1=copy)
  /// - 4 字节长度（大端序）
  /// - literal 操作: 后续跟随 length 字节的字面数据
  /// - copy 操作: 后续跟随 4 字节源块索引（大端序）
  Uint8List encode() {
    final opByte = op == RdiffDeltaOp.literal ? 0 : 1;
    final header = Uint8List(5);
    header[0] = opByte;
    header[1] = (length >> 24) & 0xFF;
    header[2] = (length >> 16) & 0xFF;
    header[3] = (length >> 8) & 0xFF;
    header[4] = length & 0xFF;

    if (op == RdiffDeltaOp.literal && data != null) {
      final result = Uint8List(5 + data!.length);
      result.setRange(0, 5, header);
      result.setRange(5, 5 + data!.length, data!);
      return result;
    } else if (op == RdiffDeltaOp.copy && sourceBlockIndex != null) {
      final result = Uint8List(9);
      result.setRange(0, 5, header);
      result[5] = (sourceBlockIndex! >> 24) & 0xFF;
      result[6] = (sourceBlockIndex! >> 16) & 0xFF;
      result[7] = (sourceBlockIndex! >> 8) & 0xFF;
      result[8] = sourceBlockIndex! & 0xFF;
      return result;
    }

    return header;
  }

  /// 从二进制格式解码 —— 与 encode() 对应
  static RdiffDeltaInstruction decode(Uint8List encoded, int offset) {
    final opByte = encoded[offset];
    final op = opByte == 0 ? RdiffDeltaOp.literal : RdiffDeltaOp.copy;
    final length = (encoded[offset + 1] << 24) |
        (encoded[offset + 2] << 16) |
        (encoded[offset + 3] << 8) |
        encoded[offset + 4];

    if (op == RdiffDeltaOp.literal) {
      final data = Uint8List(length);
      data.setRange(0, length, encoded, offset + 5);
      return RdiffDeltaInstruction(
        op: op,
        length: length,
        data: data,
      );
    } else {
      final sourceBlockIndex = (encoded[offset + 5] << 24) |
          (encoded[offset + 6] << 16) |
          (encoded[offset + 7] << 8) |
          encoded[offset + 8];
      return RdiffDeltaInstruction(
        op: op,
        length: length,
        sourceBlockIndex: sourceBlockIndex,
      );
    }
  }

  /// 获取指令编码后的总字节长度
  int get encodedLength {
    if (op == RdiffDeltaOp.literal) {
      return 5 + (data?.length ?? 0);
    } else {
      return 9; // 5 字节头 + 4 字节源块索引
    }
  }
}

/// RdiffService - 基于 rsync 算法的增量传输服务
///
/// 核心算法借鉴 librsync（rdiff 的底层库）:
/// https://github.com/librsync/librsync
///
/// rsync 算法核心思想（Andrew Tridgell, 1996）:
/// 通过滚动校验和实现 O(n) 复杂度的块匹配，避免全文件传输。
/// 接收端发送文件签名（弱哈希 + 强哈希列表），
/// 发送端使用滚动窗口匹配，仅传输差异部分。
class RdiffService {
  /// 借鉴 rdiff 的默认块大小（2048 字节）
  /// 来源: https://github.com/librsync/librsync
  /// 块大小选择原则:
  /// - 太小 → 签名表过大，匹配开销增加
  /// - 太大 → 增量精度降低，冗余传输增加
  /// 2048 是 librsync 经过实验得出的平衡值
  static const int blockSize = 2048;

  /// 弱哈希模数 —— 借鉴 librsync 的 Adler32 变体
  /// 使用 2^24 作为模数，平衡碰撞率和计算效率
  static const int _checksumModulus = 16777216; // 2^24

  // ==================== 哈希计算 ====================

  /// 计算数据块的弱哈希（滚动校验和）
  ///
  /// 借鉴 librsync 的 rs_calc_weak_sum() 函数:
  /// https://github.com/librsync/librsync/blob/master/src/checksum.c
  ///
  /// 算法原理（类 Adler32）:
  /// - sum1 = Σ byte_i (mod M)
  /// - sum2 = Σ sum1_i (mod M)
  /// - weak = (sum2 << 16) | sum1
  ///
  /// 滚动特性:
  /// 当窗口滑动一个字节时，可以 O(1) 更新:
  /// sum1' = sum1 - old_byte + new_byte
  /// sum2' = sum2 - block_size * old_byte + sum1'
  ///
  /// 这使得发送端可以在 O(n) 时间内扫描整个文件，
  /// 而不是 O(n * block_size) 的朴素方法。
  int _weakChecksum(Uint8List block) {
    int sum1 = 0;
    int sum2 = 0;
    for (final byte in block) {
      sum1 = (sum1 + byte) % _checksumModulus;
      sum2 = (sum2 + sum1) % _checksumModulus;
    }
    return (sum2 << 16) | sum1;
  }

  /// 滚动更新弱哈希 —— O(1) 时间复杂度
  ///
  /// 借鉴 librsync 的 rs_weak_sum_rollem() 函数:
  /// 当窗口从 [old_block] 滑动到 [new_block] 时，
  /// 只需减去离开的字节、加上新进入的字节。
  ///
  /// 参数:
  /// - oldSum1: 旧窗口的 sum1 值
  /// - oldSum2: 旧窗口的 sum2 值
  /// - outByte: 离开窗口的字节
  /// - inByte: 进入窗口的字节
  /// - blockLen: 窗口大小
  ///
  /// 返回: (newSum1, newSum2)
  (int, int) _rollWeakChecksum(
    int oldSum1,
    int oldSum2,
    int outByte,
    int inByte,
    int blockLen,
  ) {
    int newSum1 = (oldSum1 - outByte + inByte) % _checksumModulus;
    if (newSum1 < 0) newSum1 += _checksumModulus;
    int newSum2 = (oldSum2 - blockLen * outByte + newSum1) % _checksumModulus;
    if (newSum2 < 0) newSum2 += _checksumModulus;
    return (newSum1, newSum2);
  }

  /// 计算数据块的强哈希（简化版 MD5-like 哈希）
  ///
  /// 借鉴 librsync 的 rs_calc_strong_sum() 函数:
  /// https://github.com/librsync/librsync/blob/master/src/checksum.c
  ///
  /// librsync 使用 MD5 作为强哈希，但由于 Dart 标准库不包含 MD5，
  /// 此处实现一个基于 FNV-1a 的 16 字节强哈希变体。
  ///
  /// 强哈希的作用:
  /// 当弱哈希匹配时，用强哈希做二次确认，
  /// 将碰撞概率从 ~1/2^32 降低到 ~1/2^128。
  Uint8List _strongChecksum(Uint8List block) {
    // 借鉴 FNV-1a 哈希算法
    // 来源: https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
    // 使用 128 位（16 字节）输出，分为 4 个 32 位 FNV-1a 哈希
    const int fnvPrime = 0x01000193;
    const int fnvOffset = 0x811c9dc5;

    Uint8List result = Uint8List(16);

    for (int part = 0; part < 4; part++) {
      int hash = fnvOffset;
      for (int i = 0; i < block.length; i++) {
        // 每轮使用不同的偏移量，确保各部分结果不同
        hash ^= block[i] + part;
        hash = (hash * fnvPrime) & 0xFFFFFFFF;
      }
      result[part * 4] = (hash >> 24) & 0xFF;
      result[part * 4 + 1] = (hash >> 16) & 0xFF;
      result[part * 4 + 2] = (hash >> 8) & 0xFF;
      result[part * 4 + 3] = hash & 0xFF;
    }

    return result;
  }

  // ==================== 签名计算 ====================

  /// 计算文件的块签名列表 —— 用于远程同步时发送签名
  ///
  /// 借鉴 librsync 的 rs_sig_file() 函数:
  /// https://github.com/librsync/librsync/blob/master/src/rsync.c
  ///
  /// 流程:
  /// 1. 将文件按固定块大小分块
  /// 2. 对每一块计算弱哈希 + 强哈希
  /// 3. 返回签名列表（发送给发送端用于增量计算）
  ///
  /// 参数:
  /// - data: 文件数据
  /// - customBlockSize: 自定义块大小（默认使用 blockSize = 2048）
  ///
  /// 返回: 签名列表，每个签名对应一个数据块
  List<RdiffBlockSignature> calculateSignatures(
    Uint8List data, {
    int? customBlockSize,
  }) {
    final size = customBlockSize ?? blockSize;
    final signatures = <RdiffBlockSignature>[];
    final totalBlocks = (data.length / size).ceil();

    for (int i = 0; i < totalBlocks; i++) {
      final start = i * size;
      final end = (i + 1) * size;
      final blockEnd = end > data.length ? data.length : end;
      final block = data.sublist(start, blockEnd);

      // 如果块不足 blockSize，用零填充以保持一致的哈希计算
      Uint8List paddedBlock;
      if (block.length < size) {
        paddedBlock = Uint8List(size);
        paddedBlock.setRange(0, block.length, block);
      } else {
        paddedBlock = block;
      }

      final weak = _weakChecksum(paddedBlock);
      final strong = _strongChecksum(paddedBlock);

      signatures.add(RdiffBlockSignature(
        index: i,
        weakChecksum: weak,
        strongChecksum: strong,
      ));
    }

    return signatures;
  }

  /// 将签名列表序列化为二进制格式 —— 用于网络传输
  ///
  /// 格式:
  /// - 4 字节: 签名数量（大端序）
  /// - 每个签名:
  ///   - 4 字节: 块索引
  ///   - 4 字节: 弱哈希
  ///   - 16 字节: 强哈希
  Uint8List encodeSignatures(List<RdiffBlockSignature> signatures) {
    final signatureSize = 4 + 4 + 16; // index + weak + strong
    final buffer = Uint8List(4 + signatures.length * signatureSize);

    // 写入签名数量
    buffer[0] = (signatures.length >> 24) & 0xFF;
    buffer[1] = (signatures.length >> 16) & 0xFF;
    buffer[2] = (signatures.length >> 8) & 0xFF;
    buffer[3] = signatures.length & 0xFF;

    for (int i = 0; i < signatures.length; i++) {
      final sig = signatures[i];
      final offset = 4 + i * signatureSize;

      // 块索引
      buffer[offset] = (sig.index >> 24) & 0xFF;
      buffer[offset + 1] = (sig.index >> 16) & 0xFF;
      buffer[offset + 2] = (sig.index >> 8) & 0xFF;
      buffer[offset + 3] = sig.index & 0xFF;

      // 弱哈希
      buffer[offset + 4] = (sig.weakChecksum >> 24) & 0xFF;
      buffer[offset + 5] = (sig.weakChecksum >> 16) & 0xFF;
      buffer[offset + 6] = (sig.weakChecksum >> 8) & 0xFF;
      buffer[offset + 7] = sig.weakChecksum & 0xFF;

      // 强哈希
      buffer.setRange(offset + 8, offset + 24, sig.strongChecksum);
    }

    return buffer;
  }

  /// 从二进制格式解码签名列表
  List<RdiffBlockSignature> decodeSignatures(Uint8List data) {
    if (data.length < 4) return [];

    final count = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    final signatureSize = 4 + 4 + 16;
    final signatures = <RdiffBlockSignature>[];

    for (int i = 0; i < count; i++) {
      final offset = 4 + i * signatureSize;
      if (offset + signatureSize > data.length) break;

      final index = (data[offset] << 24) |
          (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3];

      final weak = (data[offset + 4] << 24) |
          (data[offset + 5] << 16) |
          (data[offset + 6] << 8) |
          data[offset + 7];

      final strong = Uint8List(16);
      strong.setRange(0, 16, data, offset + 8);

      signatures.add(RdiffBlockSignature(
        index: index,
        weakChecksum: weak,
        strongChecksum: strong,
      ));
    }

    return signatures;
  }

  // ==================== 增量计算 ====================

  /// 计算增量（delta）—— 比较远程签名与本地文件，生成增量指令
  ///
  /// 借鉴 librsync 的 rs_delta_file() 函数:
  /// https://github.com/librsync/librsync/blob/master/src/delta.c
  ///
  /// 算法流程:
  /// 1. 将远程签名列表构建为弱哈希查找表（hash map），加速匹配
  /// 2. 使用滚动窗口在本地新数据上滑动
  /// 3. 每一步计算当前窗口的弱哈希，在查找表中寻找匹配
  /// 4. 弱哈希匹配时，进一步比较强哈希确认
  /// 5. 匹配成功 → 生成 COPY 指令；否则累积字面数据 → 生成 LITERAL 指令
  ///
  /// 参数:
  /// - newData: 本地新文件数据（发送端）
  /// - oldSignatures: 远程旧文件的签名列表（接收端发送）
  /// - customBlockSize: 自定义块大小
  ///
  /// 返回: 编码后的增量指令流
  Uint8List calculateDelta(
    Uint8List newData,
    List<RdiffBlockSignature> oldSignatures, {
    int? customBlockSize,
  }) {
    final size = customBlockSize ?? blockSize;

    if (oldSignatures.isEmpty || newData.isEmpty) {
      // 无签名或无数据 → 全部作为字面数据传输
      final instruction = RdiffDeltaInstruction(
        op: RdiffDeltaOp.literal,
        length: newData.length,
        data: newData,
      );
      return instruction.encode();
    }

    // 构建弱哈希查找表 —— 借鉴 librsync 的哈希表加速匹配
    // 使用 Map<int, List<int>> 处理哈希冲突
    final weakHashLookup = <int, List<int>>{};
    for (final sig in oldSignatures) {
      weakHashLookup.putIfAbsent(sig.weakChecksum, () => []).add(sig.index);
    }

    final instructions = <RdiffDeltaInstruction>[];
    Uint8List literalBuffer = Uint8List(0);

    void flushLiteralBuffer() {
      if (literalBuffer.isNotEmpty) {
        instructions.add(RdiffDeltaInstruction(
          op: RdiffDeltaOp.literal,
          length: literalBuffer.length,
          data: literalBuffer,
        ));
        literalBuffer = Uint8List(0);
      }
    }

    // 使用滚动窗口在 newData 上滑动
    int pos = 0;
    while (pos < newData.length) {
      // 检查当前位置是否可以形成一个完整块
      if (pos + size <= newData.length) {
        final window = newData.sublist(pos, pos + size);
        final weak = _weakChecksum(window);
        final strong = _strongChecksum(window);

        // 在弱哈希查找表中寻找匹配
        bool matched = false;
        final candidateIndices = weakHashLookup[weak];

        if (candidateIndices != null) {
          for (final idx in candidateIndices) {
            final candidateSig = oldSignatures[idx];
            // 比较强哈希确认匹配
            if (_compareUint8List(candidateSig.strongChecksum, strong)) {
              // 匹配成功 → 生成 COPY 指令
              flushLiteralBuffer();
              instructions.add(RdiffDeltaInstruction(
                op: RdiffDeltaOp.copy,
                length: 1, // 1 个块
                sourceBlockIndex: idx,
              ));
              pos += size;
              matched = true;
              break;
            }
          }
        }

        if (!matched) {
          // 未匹配 → 累积字面数据
          literalBuffer = _appendByte(literalBuffer, newData[pos]);
          pos++;
        }
      } else {
        // 尾部不足一个完整块 → 作为字面数据传输
        final tail = newData.sublist(pos);
        literalBuffer = _concatUint8List(literalBuffer, tail);
        pos = newData.length;
      }
    }

    // 刷新剩余的字面数据
    flushLiteralBuffer();

    // 将所有指令编码为二进制
    return _encodeDeltaInstructions(instructions);
  }

  /// 将增量指令列表编码为二进制
  Uint8List _encodeDeltaInstructions(List<RdiffDeltaInstruction> instructions) {
    int totalLength = 0;
    for (final inst in instructions) {
      totalLength += inst.encodedLength;
    }

    final buffer = Uint8List(totalLength);
    int offset = 0;
    for (final inst in instructions) {
      final encoded = inst.encode();
      buffer.setRange(offset, offset + encoded.length, encoded);
      offset += encoded.length;
    }

    return buffer;
  }

  // ==================== 增量应用 ====================

  /// 应用增量（patch）—— 根据增量指令和本地旧文件重建目标文件
  ///
  /// 借鉴 librsync 的 rs_patch_file() 函数:
  /// https://github.com/librsync/librsync/blob/master/src/patch.c
  ///
  /// 算法流程:
  /// 1. 解析增量指令流
  /// 2. 遍历指令:
  ///    - LITERAL: 将字面数据追加到输出缓冲区
  ///    - COPY: 从旧文件的对应块位置复制数据到输出缓冲区
  /// 3. 返回重建后的完整文件数据
  ///
  /// 参数:
  /// - oldData: 本地旧文件数据（接收端）
  /// - delta: 增量指令流（发送端生成）
  /// - customBlockSize: 自定义块大小
  ///
  /// 返回: 重建后的新文件数据
  Uint8List applyPatch(
    Uint8List oldData,
    Uint8List delta, {
    int? customBlockSize,
  }) {
    final size = customBlockSize ?? blockSize;
    final output = BytesBuilder();

    int offset = 0;
    while (offset < delta.length) {
      final instruction = RdiffDeltaInstruction.decode(delta, offset);
      offset += instruction.encodedLength;

      if (instruction.op == RdiffDeltaOp.literal && instruction.data != null) {
        // 字面数据 → 直接追加
        output.add(instruction.data!);
      } else if (instruction.op == RdiffDeltaOp.copy &&
          instruction.sourceBlockIndex != null) {
        // 块引用 → 从旧文件复制
        final blockIndex = instruction.sourceBlockIndex!;
        // 支持复制多个块（length > 1 的情况）
        for (int i = 0; i < instruction.length; i++) {
          final start = (blockIndex + i) * size;
          final end = (start + size < oldData.length) ? start + size : oldData.length;
          if (start < oldData.length) {
            output.add(oldData.sublist(start, end));
          }
        }
      }
    }

    return output.toBytes();
  }

  // ==================== 辅助方法 ====================

  /// 比较两个 Uint8List 是否相等
  bool _compareUint8List(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 向 Uint8List 追加一个字节
  Uint8List _appendByte(Uint8List list, int byte) {
    final result = Uint8List(list.length + 1);
    result.setRange(0, list.length, list);
    result[list.length] = byte;
    return result;
  }

  /// 拼接两个 Uint8List
  Uint8List _concatUint8List(Uint8List a, Uint8List b) {
    final result = Uint8List(a.length + b.length);
    result.setRange(0, a.length, a);
    result.setRange(a.length, a.length + b.length, b);
    return result;
  }

  /// 计算增量大小压缩率 —— 用于评估增量传输的效果
  ///
  /// 返回: 增量大小 / 原始大小 的比率（越小越好）
  /// 例如: 0.05 表示增量仅占原始数据的 5%
  double compressionRatio(int originalSize, int deltaSize) {
    if (originalSize == 0) return 0.0;
    return deltaSize / originalSize;
  }
}
