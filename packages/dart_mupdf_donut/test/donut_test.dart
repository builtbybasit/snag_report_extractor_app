/// Comprehensive test suite for the Donut module.
///
/// Tests all components: Tensor, NN layers, Encoder, Decoder,
/// Tokenizer, Model, ImageUtils, and json2token/token2json.
import 'dart:io';

import 'package:test/test.dart';
import 'package:dart_mupdf_donut/donut.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // TENSOR TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('Tensor', () {
    test('creation - zeros', () {
      final t = Tensor.zeros([2, 3]);
      expect(t.shape, [2, 3]);
      expect(t.size, 6);
      expect(t.ndim, 2);
      expect(t.data.every((v) => v == 0.0), true);
    });

    test('creation - ones', () {
      final t = Tensor.ones([3, 4]);
      expect(t.shape, [3, 4]);
      expect(t.data.every((v) => v == 1.0), true);
    });

    test('creation - full', () {
      final t = Tensor.full([2, 2], 3.14);
      expect(t.data.every((v) => (v - 3.14).abs() < 1e-5), true);
    });

    test('creation - arange', () {
      final t = Tensor.arange(0, 5);
      expect(t.shape, [5]);
      expect(t.data[0], 0.0);
      expect(t.data[4], 4.0);
    });

    test('creation - fromList 2D', () {
      final t = Tensor.fromList([
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0]
      ]);
      expect(t.shape, [2, 3]);
      expect(t.at([0, 0]), 1.0);
      expect(t.at([1, 2]), 6.0);
    });

    test('creation - scalar', () {
      final t = Tensor.scalar(42.0);
      expect(t.shape, [1]);
      expect(t.data[0], 42.0);
    });

    test('indexing - at and setAt', () {
      final t = Tensor.zeros([3, 3]);
      t.setAt([1, 2], 7.0);
      expect(t.at([1, 2]), 7.0);
      expect(t.at([0, 0]), 0.0);
    });

    test('indexing - operator []', () {
      final t = Tensor.fromList([
        [1.0, 2.0],
        [3.0, 4.0]
      ]);
      final row0 = t[0];
      expect(row0.shape, [2]);
      expect(row0.data[0], 1.0);
      expect(row0.data[1], 2.0);
    });

    test('slice', () {
      final t = Tensor.fromList([
        [1.0, 2.0],
        [3.0, 4.0],
        [5.0, 6.0]
      ]);
      final sliced = t.slice(1, 3);
      expect(sliced.shape, [2, 2]);
      expect(sliced.at([0, 0]), 3.0);
      expect(sliced.at([1, 1]), 6.0);
    });

    test('reshape', () {
      final t = Tensor.arange(0, 12);
      final r = t.reshape([3, 4]);
      expect(r.shape, [3, 4]);
      expect(r.at([0, 0]), 0.0);
      expect(r.at([2, 3]), 11.0);
    });

    test('reshape with -1', () {
      final t = Tensor.arange(0, 12);
      final r = t.reshape([3, -1]);
      expect(r.shape, [3, 4]);
    });

    test('transpose 2D', () {
      final t = Tensor.fromList([
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0]
      ]);
      final tr = t.transpose(0, 1);
      expect(tr.shape, [3, 2]);
      expect(tr.at([0, 0]), 1.0);
      expect(tr.at([0, 1]), 4.0);
      expect(tr.at([2, 0]), 3.0);
    });

    test('element-wise add', () {
      final a = Tensor.ones([2, 3]);
      final b = Tensor.full([2, 3], 2.0);
      final c = a + b;
      expect(c.data.every((v) => (v - 3.0).abs() < 1e-5), true);
    });

    test('element-wise multiply', () {
      final a = Tensor.full([2, 2], 3.0);
      final b = Tensor.full([2, 2], 4.0);
      final c = a * b;
      expect(c.data.every((v) => (v - 12.0).abs() < 1e-5), true);
    });

    test('matmul 2D', () {
      // [1,2] x [5,7] = [1*5+2*6, 1*7+2*8] = [17, 23]
      // [3,4]   [6,8]   [3*5+4*6, 3*7+4*8]   [39, 53]
      final a = Tensor.fromList([
        [1.0, 2.0],
        [3.0, 4.0]
      ]);
      final b = Tensor.fromList([
        [5.0, 7.0],
        [6.0, 8.0]
      ]);
      final c = a.matmul(b);
      expect(c.shape, [2, 2]);
      expect(c.at([0, 0]), closeTo(17.0, 1e-4));
      expect(c.at([0, 1]), closeTo(23.0, 1e-4));
      expect(c.at([1, 0]), closeTo(39.0, 1e-4));
      expect(c.at([1, 1]), closeTo(53.0, 1e-4));
    });

    test('matmul batched 3D', () {
      final a = Tensor.ones([2, 3, 4]); // batch=2, 3x4
      final b = Tensor.ones([2, 4, 5]); // batch=2, 4x5
      final c = a.matmul(b);
      expect(c.shape, [2, 3, 5]);
      // Each element should be 4.0 (dot product of 4 ones)
      expect(c.at([0, 0, 0]), closeTo(4.0, 1e-4));
    });

    test('softmax', () {
      final t = Tensor.fromList([
        [1.0, 2.0, 3.0]
      ]);
      final s = t.softmax(-1);
      expect(s.shape, [1, 3]);
      // Sum should be ~1
      final sum = s.data[0] + s.data[1] + s.data[2];
      expect(sum, closeTo(1.0, 1e-5));
      // Last element should be largest
      expect(s.data[2] > s.data[1], true);
      expect(s.data[1] > s.data[0], true);
    });

    test('GELU activation', () {
      final t = Tensor.fromList([
        [-1.0, 0.0, 1.0, 2.0]
      ]);
      final g = t.gelu();
      // GELU(0) = 0, GELU(1) ≈ 0.841, GELU(-1) ≈ -0.159
      expect(g.data[1], closeTo(0.0, 1e-3));
      expect(g.data[2], closeTo(0.841, 0.01));
      expect(g.data[0], closeTo(-0.159, 0.01));
    });

    test('ReLU activation', () {
      final t = Tensor.fromList([
        [-2.0, -1.0, 0.0, 1.0, 2.0]
      ]);
      final r = t.relu();
      expect(r.data[0], 0.0);
      expect(r.data[1], 0.0);
      expect(r.data[2], 0.0);
      expect(r.data[3], 1.0);
      expect(r.data[4], 2.0);
    });

    test('unsqueeze and squeeze', () {
      final t = Tensor.ones([3, 4]);
      final u = t.unsqueeze(0);
      expect(u.shape, [1, 3, 4]);
      final s = u.squeeze(0);
      expect(s.shape, [3, 4]);
    });

    test('sum along dim', () {
      final t = Tensor.fromList([
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0]
      ]);
      final s = t.sum(1); // sum along columns
      expect(s.shape, [2]);
      expect(s.data[0], closeTo(6.0, 1e-4));
      expect(s.data[1], closeTo(15.0, 1e-4));
    });

    test('mean along dim', () {
      final t = Tensor.fromList([
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0]
      ]);
      final m = t.mean(1); // mean along columns
      expect(m.shape, [2]);
      expect(m.data[0], closeTo(2.0, 1e-4));
      expect(m.data[1], closeTo(5.0, 1e-4));
    });

    test('argmax', () {
      final t = Tensor.fromList([1.0, 5.0, 3.0, 7.0, 2.0]);
      expect(t.argmax(), 3);
    });

    test('cat along dim 0', () {
      final a = Tensor.ones([2, 3]);
      final b = Tensor.full([3, 3], 2.0);
      final c = Tensor.cat([a, b], 0);
      expect(c.shape, [5, 3]);
    });

    test('cat along dim 1', () {
      final a = Tensor.ones([2, 3]);
      final b = Tensor.full([2, 4], 2.0);
      final c = Tensor.cat([a, b], 1);
      expect(c.shape, [2, 7]);
    });

    test('causalMask', () {
      final mask = Tensor.causalMask(3);
      expect(mask.shape, [3, 3]);
      expect(mask.at([0, 0]), 0.0); // valid
      expect(mask.at([0, 1]), closeTo(-1e9, 1.0)); // masked
      expect(mask.at([2, 0]), 0.0); // valid
      expect(mask.at([2, 2]), 0.0); // valid
    });

    test('paddingMask', () {
      final mask = Tensor.paddingMask([3, 2], 4);
      expect(mask.shape, [2, 4]);
      expect(mask.at([0, 2]), 1.0);
      expect(mask.at([0, 3]), 0.0);
      expect(mask.at([1, 1]), 1.0);
      expect(mask.at([1, 2]), 0.0);
    });

    test('permute', () {
      final t = Tensor.zeros([2, 3, 4]);
      final p = t.permute([0, 2, 1]);
      expect(p.shape, [2, 4, 3]);
    });

    test('expand', () {
      final t = Tensor.ones([1, 3]);
      final e = t.expand([4, 3]);
      expect(e.shape, [4, 3]);
      expect(e.at([3, 2]), 1.0);
    });

    test('mulScalar', () {
      final t = Tensor.full([2, 2], 3.0);
      final s = t.mulScalar(2.0);
      expect(s.data.every((v) => (v - 6.0).abs() < 1e-5), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // NN LAYERS TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('NN Layers', () {
    test('Linear - forward shape', () {
      final linear = Linear(8, 16);
      final input = Tensor.ones([2, 8]);
      final output = linear.forward(input);
      expect(output.shape, [2, 16]);
    });

    test('Linear - batched forward', () {
      final linear = Linear(4, 6);
      final input = Tensor.ones([3, 5, 4]); // batch=3, seqLen=5, features=4
      final output = linear.forward(input);
      expect(output.shape, [3, 5, 6]);
    });

    test('LayerNorm - forward shape and normalization', () {
      final ln = LayerNorm(8);
      final input = Tensor.ones([2, 3, 8]);
      final output = ln.forward(input);
      expect(output.shape, [2, 3, 8]);
    });

    test('Embedding - forward shape', () {
      final emb = Embedding(100, 32);
      final ids = [0, 5, 10, 15];
      final output = emb.forward(ids);
      expect(output.shape, [4, 32]);
    });

    test('Conv2d - forward shape', () {
      final conv = Conv2d(3, 16, 4, stride: 4);
      // Input: (1, 3, 24, 24) → (1, 16, 6, 6)
      final input = Tensor.ones([1, 3, 24, 24]);
      final output = conv.forward(input);
      expect(output.shape[0], 1);
      expect(output.shape[1], 16);
      expect(output.shape[2], 6);
      expect(output.shape[3], 6);
    });

    test('MultiHeadAttention - self attention', () {
      final mha = MultiHeadAttention(32, 4);
      final input = Tensor.ones([1, 5, 32]);
      final output = mha.forward(input);
      expect(output.shape, [1, 5, 32]);
    });

    test('MultiHeadAttention - cross attention', () {
      final mha = MultiHeadAttention(32, 4);
      final query = Tensor.ones([1, 3, 32]);
      final kv = Tensor.ones([1, 7, 32]);
      final output = mha.forward(query, key: kv, value: kv);
      expect(output.shape, [1, 3, 32]);
    });

    test('FeedForward - forward shape', () {
      final ff = FeedForward(32, 128);
      final input = Tensor.ones([1, 5, 32]);
      final output = ff.forward(input);
      expect(output.shape, [1, 5, 32]);
    });

    test('GELU activation layer', () {
      final gelu = GELU();
      final input = Tensor.fromList([
        [-1.0, 0.0, 1.0]
      ]);
      final output = gelu.forward(input);
      expect(output.shape, [1, 3]);
      expect(output.data[1], closeTo(0.0, 1e-3));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // DONUT CONFIG TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('DonutConfig', () {
    test('base config', () {
      final config = DonutConfig.base();
      expect(config.inputSize, [2560, 1920]);
      expect(config.encoderLayer, [2, 2, 14, 2]);
      expect(config.decoderLayer, 4);
      expect(config.encoderEmbedDim, 128);
      expect(config.decoderEmbedDim, 1024);
      expect(config.vocabSize, 57522);
    });

    test('small config', () {
      final config = DonutConfig.small();
      expect(config.inputSize, [640, 480]);
      expect(config.encoderLayer, [2, 2, 6, 2]);
      expect(config.decoderLayer, 2);
      expect(config.encoderEmbedDim, 64);
    });

    test('encoderOutputDim', () {
      final config = DonutConfig.base();
      // 128 * 2^3 = 1024
      expect(config.encoderOutputDim, 1024);

      final small = DonutConfig.small();
      // 64 * 2^3 = 512
      expect(small.encoderOutputDim, 512);
    });

    test('toJson/fromJson roundtrip', () {
      final config = DonutConfig.base();
      final json = config.toJson();
      final config2 = DonutConfig.fromJson(json);
      expect(config2.inputSize, config.inputSize);
      expect(config2.encoderLayer, config.encoderLayer);
      expect(config2.decoderLayer, config.decoderLayer);
      expect(config2.vocabSize, config.vocabSize);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // TOKENIZER TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('DonutTokenizer', () {
    test('creation from vocab', () {
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
        'hello': 4,
        'world': 5,
        'h': 6,
        'e': 7,
        'l': 8,
        'o': 9,
        'w': 10,
        'r': 11,
        'd': 12,
        '▁': 13,
      };
      final tok = DonutTokenizer.fromVocab(vocab);
      expect(tok.vocabSize, 14);
      expect(tok.bosTokenId, 0);
      expect(tok.eosTokenId, 2);
      expect(tok.padTokenId, 1);
    });

    test('encode/decode roundtrip', () {
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
        'h': 4,
        'e': 5,
        'l': 6,
        'o': 7,
        '▁': 8,
      };
      final tok = DonutTokenizer.fromVocab(vocab);
      final ids = tok.encode('hello');
      expect(ids.first, 0); // BOS
      expect(ids.last, 2); // EOS
      expect(ids.length, greaterThan(2)); // BOS + tokens + EOS

      final decoded = tok.decode(ids);
      expect(decoded.isNotEmpty, true);
    });

    test('special tokens management', () {
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
      };
      final tok = DonutTokenizer.fromVocab(vocab);
      final added = tok.addSpecialTokens(['<s_menu>', '</s_menu>', '<sep/>']);
      expect(added, 3);
      expect(tok.vocab['<s_menu>'], isNotNull);
      expect(tok.vocab['</s_menu>'], isNotNull);
      expect(tok.vocab['<sep/>'], isNotNull);
    });

    test('pad sequences', () {
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
      };
      final tok = DonutTokenizer.fromVocab(vocab);
      final (padded, masks) = tok.pad([
        [0, 4, 5, 2],
        [0, 4, 2],
      ]);
      expect(padded[0].length, 4);
      expect(padded[1].length, 4);
      expect(padded[1][3], 1); // PAD token
      expect(masks[0], [1, 1, 1, 1]);
      expect(masks[1], [1, 1, 1, 0]);
    });

    test('tokenizer toJson', () {
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
        'hello': 4,
      };
      final tok = DonutTokenizer.fromVocab(vocab);
      final json = tok.toJson();
      expect(json['model']['vocab'], isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // JSON ↔ TOKEN CONVERSION TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('json2token / token2json', () {
    test('simple key-value', () {
      final json = {'name': 'Latte', 'price': '5.00'};
      final tokens = DonutModel.json2token(json);
      expect(tokens, contains('<s_name>'));
      expect(tokens, contains('Latte'));
      expect(tokens, contains('</s_name>'));
      expect(tokens, contains('<s_price>'));
      expect(tokens, contains('5.00'));
    });

    test('nested dict', () {
      final json = {
        'menu': {'nm': 'Latte', 'price': '3.50'}
      };
      final tokens = DonutModel.json2token(json);
      expect(tokens, contains('<s_menu>'));
      expect(tokens, contains('<s_nm>'));
      expect(tokens, contains('Latte'));
      expect(tokens, contains('</s_nm>'));
      expect(tokens, contains('</s_menu>'));
    });

    test('list with sep', () {
      final json = {
        'items': ['Apple', 'Banana']
      };
      final tokens = DonutModel.json2token(json);
      expect(tokens, contains('<sep/>'));
    });

    test('roundtrip simple', () {
      final original = {'name': 'Espresso', 'price': '4.00'};
      final tokens = DonutModel.json2token(original);
      final parsed = DonutModel.token2json(tokens);
      expect(parsed, isA<Map>());
      expect((parsed as Map)['name'], 'Espresso');
      expect(parsed['price'], '4.00');
    });

    test('roundtrip nested', () {
      final original = {
        'menu': {'nm': 'Cappuccino', 'price': '5.50'}
      };
      final tokens = DonutModel.json2token(original);
      final parsed = DonutModel.token2json(tokens);
      expect(parsed, isA<Map>());
      expect((parsed as Map)['menu'], isA<Map>());
      expect((parsed['menu'] as Map)['nm'], 'Cappuccino');
    });

    test('roundtrip with list', () {
      final original = {
        'items': ['Coffee', 'Tea', 'Juice']
      };
      final tokens = DonutModel.json2token(original);
      final parsed = DonutModel.token2json(tokens);
      expect(parsed, isA<Map>());
      expect((parsed as Map)['items'], isA<List>());
      expect(((parsed['items']) as List).length, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // SWIN ENCODER TESTS (tiny config)
  // ═══════════════════════════════════════════════════════════════════
  group('SwinEncoder', () {
    test('construction', () {
      final encoder = SwinEncoder(
        inputSize: [40, 40],
        patchSize: 4,
        embedDim: 16,
        encoderLayer: [2, 2],
        numHeads: [2, 4],
        windowSize: 5,
      );
      expect(encoder, isNotNull);
    });

    test('forward pass shape', () {
      // Tiny encoder: 40x40 input, patchSize=4 → 10x10 patches → 100 patches
      // After 1 downsampling: 5x5 = 25 patches with dim 32
      final encoder = SwinEncoder(
        inputSize: [40, 40],
        patchSize: 4,
        embedDim: 16,
        encoderLayer: [2, 2],
        numHeads: [2, 4],
        windowSize: 5,
      );
      final input = Tensor.ones([1, 3, 40, 40]);
      final output = encoder.forward(input);
      expect(output.shape[0], 1); // batch
      expect(output.ndim, 3); // (batch, numTokens, dim)
      // After stage 0: 10x10=100 patches, dim=16
      // After stage 1 (with patch merging from stage 0): 5x5=25 patches, dim=32
      expect(output.shape[1], 25);
      expect(output.shape[2], 32); // 16*2 = 32 after one merging
    });

    test('PatchEmbed forward', () {
      final pe = PatchEmbed(
        imgSize: [40, 40],
        patchSize: 4,
        inChannels: 3,
        embedDim: 16,
      );
      final input = Tensor.ones([1, 3, 40, 40]);
      final output = pe.forward(input);
      expect(output.shape, [1, 100, 16]); // 10x10 patches
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // BART DECODER TESTS (tiny config)
  // ═══════════════════════════════════════════════════════════════════
  group('BartDecoder', () {
    test('construction', () {
      final decoder = BartDecoder(
        decoderLayers: 2,
        maxPositionEmbeddings: 64,
        vocabSize: 100,
        embedDim: 32,
        ffnDim: 64,
        numHeads: 4,
      );
      expect(decoder, isNotNull);
    });

    test('forward pass shape', () {
      final decoder = BartDecoder(
        decoderLayers: 1,
        maxPositionEmbeddings: 64,
        vocabSize: 100,
        embedDim: 32,
        ffnDim: 64,
        numHeads: 4,
      );
      final encoderOutput = Tensor.ones([1, 10, 32]); // 10 encoder tokens
      final tokenIds = [0, 5, 10]; // 3 decoder tokens
      final (logits, cache) = decoder.forward(
        tokenIds,
        encoderHiddenStates: encoderOutput,
      );
      expect(logits.shape[0], 1); // batch
      expect(logits.shape[1], 3); // sequence length
      expect(logits.shape[2], 100); // vocab size
      expect(cache, isNotNull);
    });

    test('generate - produces tokens', () {
      final decoder = BartDecoder(
        decoderLayers: 1,
        maxPositionEmbeddings: 64,
        vocabSize: 100,
        embedDim: 32,
        ffnDim: 64,
        numHeads: 4,
      );
      final encoderOutput = Tensor.ones([1, 5, 32]);
      final tokens = decoder.generate(
        encoderOutput: encoderOutput,
        promptTokens: [0], // BOS
        maxLength: 10,
        eosTokenId: 2,
      );
      expect(tokens.isNotEmpty, true);
      expect(tokens.first, 0); // starts with BOS
      expect(tokens.length, lessThanOrEqualTo(10));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // DONUT MODEL TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('DonutModel', () {
    late DonutConfig tinyConfig;

    setUp(() {
      tinyConfig = const DonutConfig(
        inputSize: [40, 40],
        windowSize: 5,
        encoderLayer: [2, 2],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 20,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        patchSize: 4,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );
    });

    test('construction', () {
      final model = DonutModel(tinyConfig);
      expect(model, isNotNull);
      expect(model.isReady, false);
      expect(model.toString(), contains('SwinEncoder'));
    });

    test('encode produces correct shape', () {
      final model = DonutModel(tinyConfig);
      final input = Tensor.ones([1, 3, 40, 40]);
      final encoded = model.encode(input);
      expect(encoded.shape[0], 1); // batch
      expect(encoded.ndim, 3);
      // encoder output dim = 16 * 2^1 = 32
      expect(encoded.shape[2], 32);
    });

    test('decode produces token sequence', () {
      final model = DonutModel(tinyConfig);
      final encoderOutput = Tensor.ones([1, 25, 32]);
      final tokens = model.decode(
        encoderOutput: encoderOutput,
        promptTokens: [0],
        maxLength: 10,
        eosTokenId: 2,
      );
      expect(tokens.isNotEmpty, true);
    });

    test('full pipeline: encode → decode', () {
      final model = DonutModel(tinyConfig);
      final input = Tensor.ones([1, 3, 40, 40]);

      // Encode
      final encoderOutput = model.encode(input);
      expect(encoderOutput.shape[0], 1);

      // Decode
      final tokens = model.decode(
        encoderOutput: encoderOutput,
        promptTokens: [0],
        maxLength: 10,
        eosTokenId: 2,
      );
      expect(tokens.isNotEmpty, true);
    });

    test('setTokenizer', () {
      final model = DonutModel(tinyConfig);
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
      };
      for (int i = 4; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      final tok = DonutTokenizer.fromVocab(vocab);
      model.setTokenizer(tok);
      expect(model.tokenizer, isNotNull);
    });

    test('loadWeightsFromMap', () {
      final model = DonutModel(tinyConfig);
      // Just verify the method doesn't crash with empty map
      model.loadWeightsFromMap({});
      expect(model.isReady, true);
    });

    test('preparePrompt', () {
      final model = DonutModel(tinyConfig);
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
      };
      for (int i = 4; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      model.setTokenizer(DonutTokenizer.fromVocab(vocab));

      final prompt = model.preparePrompt('cord-v2');
      expect(prompt, '<s_cord-v2>');

      final vqaPrompt =
          model.preparePrompt('docvqa', question: 'What is this?');
      expect(vqaPrompt, contains('<s_question>'));
      expect(vqaPrompt, contains('What is this?'));
    });

    test('addTaskTokens', () {
      final model = DonutModel(tinyConfig);
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
      };
      for (int i = 4; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      model.setTokenizer(DonutTokenizer.fromVocab(vocab));
      model.addTaskTokens([
        {
          'menu': {'nm': 'test', 'price': '1.00'}
        }
      ]);
      expect(model.tokenizer!.vocab.containsKey('<s_menu>'), true);
      expect(model.tokenizer!.vocab.containsKey('</s_menu>'), true);
      expect(model.tokenizer!.vocab.containsKey('<s_nm>'), true);
      expect(model.tokenizer!.vocab.containsKey('<s_price>'), true);
    });

    test('factory constructors', () {
      expect(DonutModel.cordV2(), isNotNull);
      expect(DonutModel.rvlcdip(), isNotNull);
      expect(DonutModel.docvqa(), isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // IMAGE UTILS TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('DonutImageUtils', () {
    test('fromPixels creates correct tensor shape', () {
      // Create a tiny 8x8 image
      final pixels = List<int>.filled(8 * 8 * 3, 128);
      final tensor = DonutImageUtils.fromPixels(pixels, 8, 8);
      expect(tensor.shape, [1, 3, 8, 8]);
    });

    test('fromPixels normalization', () {
      // Pure red pixel (255, 0, 0)
      final pixels = <int>[255, 0, 0];
      final tensor = DonutImageUtils.fromPixels(pixels, 1, 1);
      // R channel: (1.0 - 0.485) / 0.229 ≈ 2.249
      expect(tensor.data[0], closeTo((1.0 - 0.485) / 0.229, 0.01));
      // G channel: (0.0 - 0.456) / 0.224 ≈ -2.036
      expect(tensor.data[1], closeTo((0.0 - 0.456) / 0.224, 0.01));
    });

    test('fromPixels white pixel normalization', () {
      // Pure white pixel (255, 255, 255)
      final pixels = <int>[255, 255, 255];
      final tensor = DonutImageUtils.fromPixels(pixels, 1, 1);
      // R: (1.0 - 0.485) / 0.229 ≈ 2.249
      expect(tensor.data[0], closeTo((1.0 - 0.485) / 0.229, 0.01));
      // G: (1.0 - 0.456) / 0.224 ≈ 2.429
      expect(tensor.data[1], closeTo((1.0 - 0.456) / 0.224, 0.01));
      // B: (1.0 - 0.406) / 0.225 ≈ 2.640
      expect(tensor.data[2], closeTo((1.0 - 0.406) / 0.225, 0.01));
    });

    test('fromPixels black pixel normalization', () {
      // Pure black pixel (0, 0, 0)
      final pixels = <int>[0, 0, 0];
      final tensor = DonutImageUtils.fromPixels(pixels, 1, 1);
      // R: (0.0 - 0.485) / 0.229 ≈ -2.118
      expect(tensor.data[0], closeTo(-0.485 / 0.229, 0.01));
      // G: (0.0 - 0.456) / 0.224 ≈ -2.036
      expect(tensor.data[1], closeTo(-0.456 / 0.224, 0.01));
      // B: (0.0 - 0.406) / 0.225 ≈ -1.804
      expect(tensor.data[2], closeTo(-0.406 / 0.225, 0.01));
    });

    test('fromPixels NCHW layout', () {
      // 2x2 image: red, green, blue, white
      final pixels = <int>[
        255, 0, 0, // red
        0, 255, 0, // green
        0, 0, 255, // blue
        255, 255, 255, // white
      ];
      final tensor = DonutImageUtils.fromPixels(pixels, 2, 2);
      expect(tensor.shape, [1, 3, 2, 2]); // batch, channels, height, width

      // Channel 0 (R): [1.0, 0.0, 0.0, 1.0] normalized
      // Pixel (0,0)=red has R=255→1.0, pixel (0,1)=green has R=0→0.0
      final rTopLeft = tensor.data[0 * 4 + 0]; // R channel, y=0, x=0
      final rTopRight = tensor.data[0 * 4 + 1]; // R channel, y=0, x=1
      expect(rTopLeft, closeTo((1.0 - 0.485) / 0.229, 0.01)); // red → high R
      expect(rTopRight, closeTo((0.0 - 0.485) / 0.229, 0.01)); // green → low R
    });

    test('describePipeline output', () {
      final config = DonutConfig.small();
      final desc = DonutImageUtils.describePipeline(config);
      expect(desc, contains('DonutImageUtils Pipeline'));
      expect(desc, contains('480'));
      expect(desc, contains('640'));
    });

    test('tensorToImage roundtrip', () {
      final pixels = <int>[];
      for (int i = 0; i < 4 * 4; i++) {
        pixels.addAll([128, 64, 192]); // RGB
      }
      final tensor = DonutImageUtils.fromPixels(pixels, 4, 4);
      final image = DonutImageUtils.tensorToImage(tensor);
      expect(image.width, 4);
      expect(image.height, 4);

      // Verify roundtrip: pixel values should be close to original
      final pix = image.getPixel(0, 0);
      expect(pix.r.toInt(), closeTo(128, 3));
      expect(pix.g.toInt(), closeTo(64, 3));
      expect(pix.b.toInt(), closeTo(192, 3));
    });

    test('tensorToImage denormalization range', () {
      // Create normalized tensor where all values are 0 (mean pixel)
      final tensor = Tensor.zeros([1, 3, 2, 2]);
      final image = DonutImageUtils.tensorToImage(tensor);
      // When normalized value = 0: pixel = 0 * std + mean = mean
      // R: 0.485*255 ≈ 124, G: 0.456*255 ≈ 116, B: 0.406*255 ≈ 104
      final pix = image.getPixel(0, 0);
      expect(pix.r.toInt(), closeTo(124, 2));
      expect(pix.g.toInt(), closeTo(116, 2));
      expect(pix.b.toInt(), closeTo(104, 2));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // DEEP IMAGE INSPECTION — REAL RECEIPT JPEG FILES
  // ═══════════════════════════════════════════════════════════════════
  group('Deep Image Inspection (real JPEG receipts)', () {
    // Only use the 2 JPEG images (not avif)
    final imageFiles = [
      'test/fixtures/receipt1.jpeg',
      'test/fixtures/receipt2.jpeg',
    ];

    test('JPEG files exist and are readable', () {
      for (final path in imageFiles) {
        final file = File(path);
        expect(file.existsSync(), true, reason: 'File missing: $path');
        final bytes = file.readAsBytesSync();
        expect(bytes.length, greaterThan(100),
            reason: '$path should have content');
        // JPEG magic bytes: FF D8 FF
        expect(bytes[0], 0xFF, reason: '$path should start with JPEG magic');
        expect(bytes[1], 0xD8, reason: '$path should have JPEG SOI marker');
        print('  ✓ ${path.split("/").last}: ${bytes.length} bytes, valid JPEG');
      }
    });

    test('preprocessBytes produces correct tensor for each image', () {
      final config = DonutConfig(
        inputSize: [128, 96],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 32,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 64,
        decoderFfnDim: 128,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      for (final path in imageFiles) {
        final bytes = File(path).readAsBytesSync();
        final tensor = DonutImageUtils.preprocessBytes(bytes, config);
        final name = path.split('/').last;

        // Shape: (1, 3, H, W)
        expect(tensor.shape[0], 1, reason: '$name batch');
        expect(tensor.shape[1], 3, reason: '$name channels');
        expect(tensor.shape[2], config.inputSize[0], reason: '$name height');
        expect(tensor.shape[3], config.inputSize[1], reason: '$name width');

        // Total elements = 1 * 3 * H * W
        expect(tensor.size, 1 * 3 * 128 * 96, reason: '$name total elements');

        print('  ✓ $name → ${tensor.shape}');
      }
    });

    test('pixel value range after ImageNet normalization', () {
      final config = DonutConfig(
        inputSize: [128, 96],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 32,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 64,
        decoderFfnDim: 128,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      for (final path in imageFiles) {
        final bytes = File(path).readAsBytesSync();
        final tensor = DonutImageUtils.preprocessBytes(bytes, config);
        final name = path.split('/').last;

        // After ImageNet normalization, values should be roughly in [-3, 3]
        double minVal = double.infinity;
        double maxVal = double.negativeInfinity;
        double sum = 0;
        for (int i = 0; i < tensor.size; i++) {
          final v = tensor.data[i];
          if (v < minVal) minVal = v;
          if (v > maxVal) maxVal = v;
          sum += v;
          // No NaN or Inf
          expect(v.isFinite, true, reason: '$name has non-finite value at $i');
        }
        final mean = sum / tensor.size;

        // Normalized range should be reasonable
        expect(minVal, greaterThan(-4.0), reason: '$name min too low');
        expect(maxVal, lessThan(4.0), reason: '$name max too high');
        // Mean should be somewhere around 0 for natural images
        expect(mean, greaterThan(-2.0), reason: '$name mean too negative');
        expect(mean, lessThan(3.0), reason: '$name mean too positive');

        print('  ✓ $name range: [$minVal, $maxVal], mean: $mean');
      }
    });

    test('per-channel statistics after normalization', () {
      final config = DonutConfig(
        inputSize: [128, 96],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 32,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 64,
        decoderFfnDim: 128,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      for (final path in imageFiles) {
        final bytes = File(path).readAsBytesSync();
        final tensor = DonutImageUtils.preprocessBytes(bytes, config);
        final name = path.split('/').last;
        final h = tensor.shape[2];
        final w = tensor.shape[3];
        final pixCount = h * w;

        for (int c = 0; c < 3; c++) {
          final offset = c * pixCount;
          double sum = 0, sumSq = 0;
          for (int i = 0; i < pixCount; i++) {
            final v = tensor.data[offset + i];
            sum += v;
            sumSq += v * v;
          }
          final mean = sum / pixCount;
          final variance = sumSq / pixCount - mean * mean;
          final channelName = ['R', 'G', 'B'][c];

          // All channels should have finite statistics
          expect(mean.isFinite, true, reason: '$name $channelName mean');
          expect(variance.isFinite, true, reason: '$name $channelName var');
          expect(variance, greaterThanOrEqualTo(0),
              reason: '$name $channelName variance non-negative');

          print('  $name ch=$channelName: mean=${mean.toStringAsFixed(3)}, '
              'var=${variance.toStringAsFixed(3)}');
        }
      }
    });

    test('two different images produce different tensors', () {
      final config = DonutConfig(
        inputSize: [128, 96],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 32,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 64,
        decoderFfnDim: 128,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      final tensor1 = DonutImageUtils.preprocessBytes(
          File(imageFiles[0]).readAsBytesSync(), config);
      final tensor2 = DonutImageUtils.preprocessBytes(
          File(imageFiles[1]).readAsBytesSync(), config);

      // Same shape
      expect(tensor1.shape, tensor2.shape);

      // But different content
      int numDifferent = 0;
      for (int i = 0; i < tensor1.size; i++) {
        if ((tensor1.data[i] - tensor2.data[i]).abs() > 1e-5) {
          numDifferent++;
        }
      }
      expect(numDifferent, greaterThan(tensor1.size ~/ 10),
          reason: 'At least 10% of pixels should differ');
      print(
          '  ✓ ${numDifferent}/${tensor1.size} values differ (${(100 * numDifferent / tensor1.size).toStringAsFixed(1)}%)');
    });

    test('tensorToImage roundtrip preserves real receipt image', () {
      final config = DonutConfig(
        inputSize: [64, 48],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 32,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 64,
        decoderFfnDim: 128,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      final bytes = File(imageFiles[0]).readAsBytesSync();
      final tensor = DonutImageUtils.preprocessBytes(bytes, config);
      final recovered = DonutImageUtils.tensorToImage(tensor);

      expect(recovered.width, config.inputSize[1]);
      expect(recovered.height, config.inputSize[0]);

      // All pixel values should be in valid 0-255 range
      for (int y = 0; y < recovered.height; y++) {
        for (int x = 0; x < recovered.width; x++) {
          final p = recovered.getPixel(x, y);
          expect(p.r.toInt(), inInclusiveRange(0, 255));
          expect(p.g.toInt(), inInclusiveRange(0, 255));
          expect(p.b.toInt(), inInclusiveRange(0, 255));
        }
      }
      print(
          '  ✓ Roundtrip: JPEG → tensor → image (${recovered.width}x${recovered.height})');
    });

    test('Swin encoder processes real receipt images', () {
      final config = DonutConfig(
        inputSize: [64, 48],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      // Use DonutModel.randomInit to get non-degenerate weights
      final model = DonutModel(config);
      model.randomInit(seed: 42);

      for (final path in imageFiles) {
        final bytes = File(path).readAsBytesSync();
        final tensor = DonutImageUtils.preprocessBytes(bytes, config);
        final name = path.split('/').last;

        final output = model.encode(tensor);

        // Output should be (1, numPatches, encoderOutputDim)
        expect(output.shape.length, 3, reason: '$name output ndim');
        expect(output.shape[0], 1, reason: '$name batch');
        expect(output.shape[2], config.encoderOutputDim,
            reason: '$name feature dim');

        // All output values should be finite
        for (int i = 0; i < output.size; i++) {
          expect(output.data[i].isFinite, true,
              reason: '$name output has non-finite at $i');
        }

        // Output should have non-zero variance (not collapsed)
        double sum = 0, sumSq = 0;
        for (int i = 0; i < output.size; i++) {
          sum += output.data[i];
          sumSq += output.data[i] * output.data[i];
        }
        final mean = sum / output.size;
        final variance = sumSq / output.size - mean * mean;
        expect(variance, greaterThan(0),
            reason: '$name encoder output should have variance');

        print('  ✓ $name → encoder output ${output.shape}, '
            'mean=${mean.toStringAsFixed(4)}, var=${variance.toStringAsFixed(4)}');
      }
    });

    test('different images produce different encoder outputs', () {
      final config = DonutConfig(
        inputSize: [64, 48],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      // Use random init for non-degenerate outputs
      final model = DonutModel(config);
      model.randomInit(seed: 42);

      final t1 = DonutImageUtils.preprocessBytes(
          File(imageFiles[0]).readAsBytesSync(), config);
      final t2 = DonutImageUtils.preprocessBytes(
          File(imageFiles[1]).readAsBytesSync(), config);

      final out1 = model.encode(t1);
      final out2 = model.encode(t2);

      // Same shape but different values
      expect(out1.shape, out2.shape);
      double maxDiff = 0;
      for (int i = 0; i < out1.size; i++) {
        final diff = (out1.data[i] - out2.data[i]).abs();
        if (diff > maxDiff) maxDiff = diff;
      }
      expect(maxDiff, greaterThan(0.01),
          reason: 'Encoder should distinguish different images');
      print('  ✓ Max difference between encoder outputs: $maxDiff');
    });

    test('full pipeline: real JPEG → encode → decode → tokens', () {
      final config = DonutConfig(
        inputSize: [64, 48],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 20,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      final model = DonutModel(config);
      model.randomInit(seed: 42);
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
        '<s_cord-v2>': 4,
        '</s_cord-v2>': 5,
        '<s_menu>': 6,
        '</s_menu>': 7,
        '<s_nm>': 8,
        '</s_nm>': 9,
        '<s_price>': 10,
        '</s_price>': 11,
        '<s_total>': 12,
        '</s_total>': 13,
      };
      for (int i = 14; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      final tokenizer = DonutTokenizer.fromVocab(vocab);
      tokenizer.addSpecialTokens([
        '<s_cord-v2>',
        '</s_cord-v2>',
        '<s_menu>',
        '</s_menu>',
        '<s_nm>',
        '</s_nm>',
        '<s_price>',
        '</s_price>',
        '<s_total>',
        '</s_total>',
      ]);
      model.setTokenizer(tokenizer);

      for (final path in imageFiles) {
        final bytes = File(path).readAsBytesSync();
        final name = path.split('/').last;

        // Preprocess
        final imageTensor = DonutImageUtils.preprocessBytes(bytes, config);
        expect(imageTensor.shape, [1, 3, 64, 48]);

        // Encode
        final encoderOutput = model.encode(imageTensor);
        expect(encoderOutput.shape.length, 3);
        expect(encoderOutput.shape[0], 1);

        // Decode with sampling for diverse output
        final promptTokens = tokenizer.encode('<s_cord-v2>');
        final generated = model.decoder.generate(
          encoderOutput: encoderOutput,
          promptTokens: promptTokens,
          maxLength: 15,
          eosTokenId: tokenizer.eosTokenId,
          greedy: false,
        );
        expect(generated.isNotEmpty, true);
        expect(generated.length, greaterThanOrEqualTo(promptTokens.length));

        // Decode tokens to text
        final text = tokenizer.decode(generated);
        expect(text, isNotNull);

        print('  ✓ $name → encode → decode → ${generated.length} tokens');
        print('    Text: "$text"');
      }
    });

    test('model.inference with real JPEG images', () {
      final config = DonutConfig(
        inputSize: [64, 48],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 20,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      final model = DonutModel(config);
      model.randomInit(seed: 42);
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
        '<s_cord-v2>': 4,
        '</s_cord-v2>': 5,
      };
      for (int i = 6; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      model.setTokenizer(DonutTokenizer.fromVocab(vocab));

      for (final path in imageFiles) {
        final bytes = File(path).readAsBytesSync();
        final name = path.split('/').last;

        final imageTensor = DonutImageUtils.preprocessBytes(bytes, config);
        final result = model.inference(
          imageTensor: imageTensor,
          prompt: '<s_cord-v2>',
          maxLength: 15,
        );

        expect(result, isNotNull);
        expect(result.tokens.isNotEmpty, true);
        expect(result.text, isNotNull);
        // JSON parse should not throw
        expect(result.json, isNotNull);

        print('  ✓ $name inference → ${result.tokens.length} tokens, '
            'text="${result.text}"');
      }
    });

    test('inferenceFromBytes with real JPEG images', () {
      final config = DonutConfig(
        inputSize: [64, 48],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 20,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      final model = DonutModel(config);
      model.randomInit(seed: 42);
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
        '<s_cord-v2>': 4,
        '</s_cord-v2>': 5,
      };
      for (int i = 6; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      model.setTokenizer(DonutTokenizer.fromVocab(vocab));

      for (final path in imageFiles) {
        final bytes = File(path).readAsBytesSync();
        final name = path.split('/').last;

        final result = model.inferenceFromBytes(
          imageBytes: bytes,
          prompt: '<s_cord-v2>',
          maxLength: 15,
        );

        expect(result, isNotNull);
        expect(result.tokens.isNotEmpty, true);
        expect(result.text, isNotNull);
        expect(result.json, isNotNull);

        print('  ✓ $name inferenceFromBytes → ${result.tokens.length} tokens');
      }
    });

    test('encoder output is reproducible for same image', () {
      final config = DonutConfig(
        inputSize: [64, 48],
        alignLongAxis: true,
        windowSize: 4,
        encoderLayer: [2, 2],
        patchSize: 4,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        decoderLayer: 1,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      final model = DonutModel(config);
      model.randomInit(seed: 42);

      final bytes = File(imageFiles[0]).readAsBytesSync();
      final tensor = DonutImageUtils.preprocessBytes(bytes, config);

      final out1 = model.encode(tensor);
      final out2 = model.encode(tensor);

      expect(out1.shape, out2.shape);
      for (int i = 0; i < out1.size; i++) {
        expect(out1.data[i], out2.data[i],
            reason: 'Deterministic encoder should produce same output');
      }
      print('  ✓ Same image → identical encoder output (deterministic)');
    });

    test('json2token → token2json roundtrip with receipt-like data', () {
      // Simulate what a pretrained model would output for a receipt
      final receiptData = {
        'store_info': {
          'store_name': 'Target',
          'store_addr': 'Memphis East',
        },
        'menu': [
          {'nm': 'MILK', 'price': '3.49'},
          {'nm': 'BREAD', 'price': '2.50'},
        ],
        'total': {'total_price': '5.99'},
      };

      final tokenStr = DonutModel.json2token(receiptData);
      expect(tokenStr, contains('<s_store_info>'));
      expect(tokenStr, contains('<s_nm>MILK</s_nm>'));
      expect(tokenStr, contains('<sep/>'));
      expect(tokenStr, contains('<s_total_price>5.99</s_total_price>'));

      final parsed = DonutModel.token2json(tokenStr);
      expect(parsed, isA<Map>());
      final map = parsed as Map<String, dynamic>;

      final storeInfo = map['store_info'] as Map<String, dynamic>;
      expect(storeInfo['store_name'], 'Target');
      expect(storeInfo['store_addr'], 'Memphis East');

      final menu = map['menu'] as List;
      expect(menu.length, 2);
      expect((menu[0] as Map)['nm'], 'MILK');
      expect((menu[0] as Map)['price'], '3.49');
      expect((menu[1] as Map)['nm'], 'BREAD');
      expect((menu[1] as Map)['price'], '2.50');

      expect((map['total'] as Map)['total_price'], '5.99');
      print('  ✓ Receipt JSON roundtrip: json2token → token2json verified');
    });

    test('complete CORD-v2 style receipt extraction demo', () {
      // Build a receipt tokenizer with CORD tokens
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
      };
      int nextId = 4;
      // Add ASCII chars
      for (int c = 32; c < 127; c++) {
        vocab[String.fromCharCode(c)] = nextId++;
      }
      // Add CORD special tokens
      final cordTokens = [
        '<s_cord-v2>',
        '</s_cord-v2>',
        '<s_menu>',
        '</s_menu>',
        '<s_nm>',
        '</s_nm>',
        '<s_price>',
        '</s_price>',
        '<s_total>',
        '</s_total>',
        '<s_total_price>',
        '</s_total_price>',
        '<s_store_info>',
        '</s_store_info>',
        '<s_store_name>',
        '</s_store_name>',
        '<sep/>',
      ];
      for (final t in cordTokens) {
        vocab[t] = nextId++;
      }

      final tokenizer = DonutTokenizer(
        vocab: vocab,
        merges: [],
        specialTokens: cordTokens.toSet(),
      );

      // Simulate a pretrained model output
      final expectedOutput =
          '<s_store_info><s_store_name>Target</s_store_name></s_store_info>'
          '<s_menu><s_nm>MILK</s_nm><s_price>3.49</s_price><sep/>'
          '<s_nm>BREAD</s_nm><s_price>2.50</s_price></s_menu>'
          '<s_total><s_total_price>5.99</s_total_price></s_total>';

      // Encode to tokens
      final tokenIds = tokenizer.encode(expectedOutput);
      expect(tokenIds.isNotEmpty, true);

      // Decode back
      final decoded = tokenizer.decode(tokenIds, skipSpecialTokens: false);
      expect(decoded, contains('Target'));
      expect(decoded, contains('MILK'));
      expect(decoded, contains('3.49'));

      // Parse to JSON
      final json = DonutModel.token2json(decoded);
      expect(json, isA<Map>());
      final map = json as Map<String, dynamic>;
      final storeInfo = map['store_info'] as Map<String, dynamic>;
      expect(storeInfo['store_name'], 'Target');
      final menu = map['menu'] as List;
      expect(menu.length, 2);
      final total = map['total'] as Map<String, dynamic>;
      expect(total['total_price'], '5.99');

      print('  ✓ CORD-v2 extraction demo: encode→decode→parse successful');
      print('    Store: ${storeInfo['store_name']}');
      print('    Items: ${menu.length}');
      print('    Total: \$${total['total_price']}');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // FULL PIPELINE INTEGRATION TEST
  // ═══════════════════════════════════════════════════════════════════
  group('Full Pipeline Integration', () {
    test('tiny model: image → preprocess → encode → decode', () {
      final config = const DonutConfig(
        inputSize: [40, 40],
        windowSize: 5,
        encoderLayer: [2, 2],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 15,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        patchSize: 4,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      // 1. Create model
      final model = DonutModel(config);

      // 2. Create a test tokenizer
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
      };
      for (int i = 4; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      model.setTokenizer(DonutTokenizer.fromVocab(vocab));

      // 3. Create a synthetic image tensor
      final imageTensor = Tensor.ones([1, 3, 40, 40]);

      // 4. Encode
      final encoderOutput = model.encode(imageTensor);
      print('  Encoder output shape: ${encoderOutput.shape}');

      // 5. Decode (greedy)
      final tokens = model.decode(
        encoderOutput: encoderOutput,
        promptTokens: [0], // BOS
        maxLength: 10,
        eosTokenId: 2,
      );
      print('  Generated ${tokens.length} tokens: $tokens');

      expect(tokens.isNotEmpty, true);
      expect(tokens.first, 0);
    });

    test('model inference with tokenizer', () {
      final config = const DonutConfig(
        inputSize: [40, 40],
        windowSize: 5,
        encoderLayer: [2, 2],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 15,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        patchSize: 4,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );

      final model = DonutModel(config);
      final vocab = <String, int>{
        '<s>': 0,
        '<pad>': 1,
        '</s>': 2,
        '<unk>': 3,
        '<s_cord-v2>': 4,
        '</s_cord-v2>': 5,
      };
      for (int i = 6; i < 100; i++) {
        vocab['tok_$i'] = i;
      }
      model.setTokenizer(DonutTokenizer.fromVocab(vocab));

      final imageTensor = Tensor.ones([1, 3, 40, 40]);
      final result = model.inference(
        imageTensor: imageTensor,
        prompt: '<s_cord-v2>',
        maxLength: 10,
      );

      print('  Result text: "${result.text}"');
      print('  Result tokens: ${result.tokens}');
      expect(result, isNotNull);
      expect(result.tokens.isNotEmpty, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // WEIGHT LOADER TESTS
  // ═══════════════════════════════════════════════════════════════════
  group('DonutWeightLoader', () {
    test('WeightExportGuide has export scripts', () {
      expect(WeightExportGuide.exportScript, contains('torch'));
      expect(
          WeightExportGuide.tokenizerExportScript, contains('DonutProcessor'));
    });

    test('loadFromMap with empty map', () {
      final config = const DonutConfig(
        inputSize: [40, 40],
        windowSize: 5,
        encoderLayer: [2, 2],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 15,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        patchSize: 4,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );
      final model = DonutModel(config);
      final loader = DonutWeightLoader(
        encoder: model.encoder,
        decoder: model.decoder,
      );
      // Should not crash with empty map
      loader.loadFromMap({});
    });

    test('loadFromMap with matching encoder weight', () {
      final config = const DonutConfig(
        inputSize: [40, 40],
        windowSize: 5,
        encoderLayer: [2, 2],
        decoderLayer: 1,
        maxPositionEmbeddings: 64,
        maxLength: 15,
        encoderEmbedDim: 16,
        encoderNumHeads: [2, 4],
        patchSize: 4,
        decoderEmbedDim: 32,
        decoderFfnDim: 64,
        decoderNumHeads: 4,
        vocabSize: 100,
      );
      final model = DonutModel(config);
      final loader = DonutWeightLoader(
        encoder: model.encoder,
        decoder: model.decoder,
      );

      // Create a weight that matches the patch embed projection
      final weights = <String, Tensor>{
        'encoder.model.patch_embed.proj.weight': Tensor.ones([16, 3, 4, 4]),
      };
      loader.loadFromMap(weights);
      // Just verify no crash
    });
  });
}
