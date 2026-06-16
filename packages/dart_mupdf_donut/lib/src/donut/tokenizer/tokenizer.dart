/// Tokenizer implementation for Donut's BART decoder.
///
/// Implements a SentencePiece-compatible tokenizer that can load vocabulary
/// from JSON format. Supports BPE (Byte Pair Encoding) tokenization with
/// special tokens for structured document understanding.
///
/// The tokenizer converts text strings into sequences of integer token IDs
/// and vice versa, supporting the special tokens used in Donut's
/// JSON-structured output format (e.g., `<s_menu>`, `</s_menu>`, `<sep/>`).
library;

import 'dart:convert';
import 'dart:io';

// ─── Donut Tokenizer ──────────────────────────────────────────────────

/// Tokenizer for Donut model.
///
/// Supports:
/// - Loading vocabulary from tokenizer.json (HuggingFace format)
/// - BPE tokenization
/// - Special tokens (BOS, EOS, PAD, UNK, SEP)
/// - Dynamic addition of task-specific special tokens
/// - Encoding text to token IDs
/// - Decoding token IDs back to text
class DonutTokenizer {
  /// Token to ID mapping.
  final Map<String, int> vocab;

  /// ID to token mapping.
  final Map<int, String> idToToken;

  /// BPE merge rules (ordered).
  final List<(String, String)> merges;

  /// Set of special tokens.
  final Set<String> specialTokens;

  /// Special token IDs.
  int bosTokenId;
  int eosTokenId;
  int padTokenId;
  int unkTokenId;

  /// BOS token string.
  String bosToken;

  /// EOS token string.
  String eosToken;

  /// PAD token string.
  String padToken;

  /// UNK token string.
  String unkToken;

  DonutTokenizer({
    required this.vocab,
    required this.merges,
    this.bosToken = '<s>',
    this.eosToken = '</s>',
    this.padToken = '<pad>',
    this.unkToken = '<unk>',
    Set<String>? specialTokens,
  })  : idToToken = {for (final e in vocab.entries) e.value: e.key},
        specialTokens = specialTokens ?? {},
        bosTokenId = vocab['<s>'] ?? 0,
        eosTokenId = vocab['</s>'] ?? 2,
        padTokenId = vocab['<pad>'] ?? 1,
        unkTokenId = vocab['<unk>'] ?? 3 {
    this.specialTokens.addAll([bosToken, eosToken, padToken, unkToken]);
  }

  /// Vocabulary size.
  int get vocabSize => vocab.length;

  /// Load tokenizer from HuggingFace tokenizer.json format.
  ///
  /// The file should contain:
  /// - `model.vocab`: token-to-id mapping
  /// - `model.merges`: BPE merge rules
  /// - `added_tokens`: special tokens
  factory DonutTokenizer.fromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    // Extract vocabulary
    final modelData = json['model'] as Map<String, dynamic>;
    final vocabData = modelData['vocab'] as Map<String, dynamic>;
    final vocab = <String, int>{};
    for (final entry in vocabData.entries) {
      vocab[entry.key] = entry.value as int;
    }

    // Extract merges
    final mergesData = modelData['merges'] as List<dynamic>;
    final merges = <(String, String)>[];
    for (final merge in mergesData) {
      final parts = (merge as String).split(' ');
      if (parts.length == 2) {
        merges.add((parts[0], parts[1]));
      }
    }

    // Extract special tokens
    final specialTokens = <String>{};
    if (json.containsKey('added_tokens')) {
      final addedTokens = json['added_tokens'] as List<dynamic>;
      for (final token in addedTokens) {
        final content = (token as Map<String, dynamic>)['content'] as String;
        specialTokens.add(content);
      }
    }

    return DonutTokenizer(
      vocab: vocab,
      merges: merges,
      specialTokens: specialTokens,
    );
  }

  /// Load tokenizer from a file path.
  factory DonutTokenizer.fromFile(String path) {
    final content = File(path).readAsStringSync();
    return DonutTokenizer.fromJson(content);
  }

  /// Create a simple tokenizer with just a vocabulary mapping.
  ///
  /// Useful for loading from sentencepiece model files or
  /// when only the vocabulary is available.
  factory DonutTokenizer.fromVocab(Map<String, int> vocab) {
    return DonutTokenizer(
      vocab: vocab,
      merges: [],
    );
  }

  // ─── Encoding ─────────────────────────────────────────────────────

  /// Encode text to a list of token IDs.
  ///
  /// [text]: input string to tokenize
  /// [addSpecialTokens]: if true, wraps with BOS/EOS tokens
  /// [maxLength]: optional maximum sequence length (truncate if exceeded)
  List<int> encode(
    String text, {
    bool addSpecialTokens = true,
    int? maxLength,
  }) {
    final tokens = tokenize(text);
    var ids = tokens.map((t) => vocab[t] ?? unkTokenId).toList();

    if (addSpecialTokens) {
      ids = [bosTokenId, ...ids, eosTokenId];
    }

    if (maxLength != null && ids.length > maxLength) {
      ids = ids.sublist(0, maxLength);
    }

    return ids;
  }

  /// Tokenize text into a list of token strings using BPE.
  List<String> tokenize(String text) {
    if (text.isEmpty) return [];

    final result = <String>[];

    // Split on special tokens first
    final parts = _splitOnSpecialTokens(text);

    for (final part in parts) {
      if (specialTokens.contains(part) || vocab.containsKey(part)) {
        result.add(part);
      } else {
        // Apply BPE to regular text
        final bpeTokens = _applyBpe(part);
        result.addAll(bpeTokens);
      }
    }

    return result;
  }

  /// Split text preserving special tokens as separate items.
  List<String> _splitOnSpecialTokens(String text) {
    if (specialTokens.isEmpty) return [text];

    final result = <String>[];
    var remaining = text;

    while (remaining.isNotEmpty) {
      // Find the earliest special token in the remaining text
      int earliestPos = remaining.length;
      String? foundToken;

      for (final token in specialTokens) {
        final pos = remaining.indexOf(token);
        if (pos >= 0 && pos < earliestPos) {
          earliestPos = pos;
          foundToken = token;
        }
      }

      if (foundToken != null) {
        // Add text before the special token
        if (earliestPos > 0) {
          result.add(remaining.substring(0, earliestPos));
        }
        // Add the special token
        result.add(foundToken);
        remaining = remaining.substring(earliestPos + foundToken.length);
      } else {
        // No more special tokens
        result.add(remaining);
        break;
      }
    }

    return result;
  }

  /// Apply BPE tokenization to a word.
  List<String> _applyBpe(String text) {
    if (merges.isEmpty) {
      // Fallback: character-level tokenization
      return _charTokenize(text);
    }

    // Start with characters, prepend ▁ (sentencepiece space marker) for word boundaries
    var word = text.split('').toList();
    if (word.isEmpty) return [];

    // Replace spaces with ▁
    word = word.map((c) => c == ' ' ? '▁' : c).toList();

    // Apply BPE merges
    final mergeRank = <String, int>{};
    for (int i = 0; i < merges.length; i++) {
      mergeRank['${merges[i].$1} ${merges[i].$2}'] = i;
    }

    while (word.length > 1) {
      // Find the best pair to merge
      int bestRank = merges.length;
      int bestIdx = -1;

      for (int i = 0; i < word.length - 1; i++) {
        final pair = '${word[i]} ${word[i + 1]}';
        final rank = mergeRank[pair];
        if (rank != null && rank < bestRank) {
          bestRank = rank;
          bestIdx = i;
        }
      }

      if (bestIdx == -1) break;

      // Merge the best pair
      final merged = word[bestIdx] + word[bestIdx + 1];
      word = [
        ...word.sublist(0, bestIdx),
        merged,
        ...word.sublist(bestIdx + 2),
      ];
    }

    return word;
  }

  /// Fallback character-level tokenization.
  List<String> _charTokenize(String text) {
    final tokens = <String>[];
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == ' ') {
        tokens.add('▁');
      } else if (vocab.containsKey(ch)) {
        tokens.add(ch);
      } else if (vocab.containsKey('▁$ch')) {
        tokens.add('▁$ch');
      } else {
        tokens.add(ch);
      }
    }
    return tokens;
  }

  // ─── Decoding ─────────────────────────────────────────────────────

  /// Decode a list of token IDs back to text.
  ///
  /// [ids]: list of token IDs
  /// [skipSpecialTokens]: if true, removes BOS/EOS/PAD tokens
  String decode(List<int> ids, {bool skipSpecialTokens = true}) {
    final tokens = <String>[];
    for (final id in ids) {
      final token = idToToken[id];
      if (token == null) continue;

      if (skipSpecialTokens) {
        if (token == bosToken || token == eosToken || token == padToken) {
          continue;
        }
      }

      tokens.add(token);
    }

    // Join tokens and handle SentencePiece space markers
    var text = tokens.join('');
    text = text.replaceAll('▁', ' ');

    // Clean up leading space
    if (text.startsWith(' ')) {
      text = text.substring(1);
    }

    return text;
  }

  /// Batch decode: decode multiple sequences.
  List<String> batchDecode(List<List<int>> batchIds,
      {bool skipSpecialTokens = true}) {
    return batchIds
        .map((ids) => decode(ids, skipSpecialTokens: skipSpecialTokens))
        .toList();
  }

  // ─── Special Token Management ────────────────────────────────────

  /// Add special tokens to the vocabulary.
  ///
  /// Returns the number of newly added tokens.
  int addSpecialTokens(List<String> tokens) {
    int added = 0;
    for (final token in tokens) {
      if (!vocab.containsKey(token)) {
        final newId = vocab.length;
        vocab[token] = newId;
        idToToken[newId] = token;
        added++;
      }
      specialTokens.add(token);
    }
    return added;
  }

  /// Get all added vocabulary entries (special tokens that were dynamically added).
  Map<String, int> getAddedVocab() {
    final result = <String, int>{};
    for (final token in specialTokens) {
      if (vocab.containsKey(token)) {
        result[token] = vocab[token]!;
      }
    }
    return result;
  }

  /// Pad a list of token sequences to the same length.
  ///
  /// Returns padded sequences and attention masks.
  (List<List<int>>, List<List<int>>) pad(
    List<List<int>> sequences, {
    int? maxLength,
    bool padToMaxLength = false,
  }) {
    final maxLen = maxLength ??
        sequences.fold<int>(
            0, (max, seq) => seq.length > max ? seq.length : max);

    final paddedSeqs = <List<int>>[];
    final attentionMasks = <List<int>>[];

    for (final seq in sequences) {
      final padLen = maxLen - seq.length;
      paddedSeqs.add([...seq, ...List.filled(padLen, padTokenId)]);
      attentionMasks
          .add([...List.filled(seq.length, 1), ...List.filled(padLen, 0)]);
    }

    return (paddedSeqs, attentionMasks);
  }

  /// Convert tokenizer to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'model': {
        'vocab': vocab,
        'merges': merges.map((m) => '${m.$1} ${m.$2}').toList(),
      },
      'added_tokens':
          specialTokens.map((t) => {'content': t, 'id': vocab[t]}).toList(),
    };
  }

  /// Save tokenizer to a file.
  void save(String path) {
    File(path).writeAsStringSync(jsonEncode(toJson()));
  }
}
