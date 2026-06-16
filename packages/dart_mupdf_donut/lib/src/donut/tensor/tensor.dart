/// Pure Dart N-dimensional tensor implementation for neural network inference.
///
/// Provides efficient tensor operations including matrix multiplication,
/// element-wise operations, reshaping, transposing, and broadcasting.
/// Backed by Float32List for memory efficiency.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// An N-dimensional tensor backed by a flat [Float32List].
///
/// Supports common tensor operations needed for neural network inference:
/// - Element-wise: add, subtract, multiply, divide
/// - Matrix multiplication (2D and batched)
/// - Reshape, transpose, permute, squeeze, unsqueeze
/// - Reduction: sum, mean, max, softmax
/// - Slicing and indexing
class Tensor {
  /// The underlying flat data storage.
  final Float32List data;

  /// The shape of the tensor (list of dimension sizes).
  final List<int> shape;

  /// The strides for each dimension (number of elements to skip).
  late final List<int> strides;

  /// Total number of elements.
  int get size => data.length;

  /// Number of dimensions.
  int get ndim => shape.length;

  /// Creates a tensor from existing data and shape.
  ///
  /// The [data] length must equal the product of [shape] dimensions.
  Tensor(this.data, this.shape) {
    assert(_productOfShape(shape) == data.length,
        'Data length ${data.length} != shape product ${_productOfShape(shape)}');
    strides = _computeStrides(shape);
  }

  /// Creates a tensor filled with zeros.
  factory Tensor.zeros(List<int> shape) {
    final size = _productOfShape(shape);
    return Tensor(Float32List(size), List<int>.from(shape));
  }

  /// Creates a tensor filled with ones.
  factory Tensor.ones(List<int> shape) {
    final size = _productOfShape(shape);
    final data = Float32List(size);
    for (int i = 0; i < size; i++) {
      data[i] = 1.0;
    }
    return Tensor(data, List<int>.from(shape));
  }

  /// Creates a tensor filled with a constant value.
  factory Tensor.full(List<int> shape, double value) {
    final size = _productOfShape(shape);
    final data = Float32List(size);
    for (int i = 0; i < size; i++) {
      data[i] = value;
    }
    return Tensor(data, List<int>.from(shape));
  }

  /// Creates a 1D tensor with values from [start] to [end] (exclusive).
  factory Tensor.arange(int start, int end) {
    final data = Float32List(end - start);
    for (int i = 0; i < data.length; i++) {
      data[i] = (start + i).toDouble();
    }
    return Tensor(data, [data.length]);
  }

  /// Creates a tensor from a nested list of doubles.
  factory Tensor.fromList(List<dynamic> list) {
    final shape = <int>[];
    dynamic current = list;
    while (current is List) {
      shape.add(current.length);
      if (current.isEmpty) break;
      current = current[0];
    }
    final flat = <double>[];
    _flattenList(list, flat);
    return Tensor(Float32List.fromList(flat), shape);
  }

  /// Creates a scalar tensor (shape = [1]).
  factory Tensor.scalar(double value) {
    return Tensor(Float32List.fromList([value]), [1]);
  }

  /// Creates a tensor with random values from a normal distribution.
  ///
  /// Uses Box-Muller transform to generate N(0, 1) samples,
  /// then scales by [std] and shifts by [mean].
  factory Tensor.randn(List<int> shape,
      {double mean = 0.0, double std = 1.0, int? seed}) {
    final size = _productOfShape(shape);
    final data = Float32List(size);
    final rng = seed != null ? math.Random(seed) : math.Random();
    // Box-Muller transform: pairs of uniform → normal
    for (int i = 0; i < size - 1; i += 2) {
      final u1 = rng.nextDouble();
      final u2 = rng.nextDouble();
      final r = math.sqrt(-2.0 * math.log(u1 == 0 ? 1e-10 : u1));
      final theta = 2.0 * math.pi * u2;
      data[i] = (r * math.cos(theta) * std + mean).toDouble();
      data[i + 1] = (r * math.sin(theta) * std + mean).toDouble();
    }
    // Handle odd size
    if (size.isOdd) {
      final u1 = rng.nextDouble();
      final u2 = rng.nextDouble();
      final r = math.sqrt(-2.0 * math.log(u1 == 0 ? 1e-10 : u1));
      data[size - 1] =
          (r * math.cos(2.0 * math.pi * u2) * std + mean).toDouble();
    }
    return Tensor(data, List<int>.from(shape));
  }

  static void _flattenList(dynamic list, List<double> out) {
    if (list is List) {
      for (final item in list) {
        _flattenList(item, out);
      }
    } else {
      out.add((list as num).toDouble());
    }
  }

  // ─── Indexing ───────────────────────────────────────────────────────

  /// Get a single element by multi-dimensional index.
  double at(List<int> indices) {
    assert(indices.length == ndim);
    int offset = 0;
    for (int i = 0; i < ndim; i++) {
      offset += indices[i] * strides[i];
    }
    return data[offset];
  }

  /// Set a single element by multi-dimensional index.
  void setAt(List<int> indices, double value) {
    assert(indices.length == ndim);
    int offset = 0;
    for (int i = 0; i < ndim; i++) {
      offset += indices[i] * strides[i];
    }
    data[offset] = value;
  }

  /// Get a sub-tensor along the first dimension.
  Tensor operator [](int index) {
    if (ndim == 1) {
      return Tensor(Float32List.fromList([data[index]]), [1]);
    }
    final newShape = shape.sublist(1);
    final stride = strides[0];
    final start = index * stride;
    final newData = Float32List.sublistView(data, start, start + stride);
    return Tensor(Float32List.fromList(newData), List<int>.from(newShape));
  }

  /// Slice: returns a sub-tensor from [start] to [end] along dimension 0.
  Tensor slice(int start, int end, [int dim = 0]) {
    if (dim == 0) {
      final stride = strides[0];
      final s = start * stride;
      final e = end * stride;
      final newData = Float32List.fromList(data.sublist(s, e));
      final newShape = List<int>.from(shape);
      newShape[0] = end - start;
      return Tensor(newData, newShape);
    }
    // General dim slicing — build by iterating
    return _sliceGeneral(start, end, dim);
  }

  Tensor _sliceGeneral(int start, int end, int dim) {
    final newShape = List<int>.from(shape);
    newShape[dim] = end - start;
    final result = Tensor.zeros(newShape);
    final totalOuter = _productOfShape(shape.sublist(0, dim));
    final innerSize = _productOfShape(shape.sublist(dim + 1));
    final dimSize = shape[dim];
    final newDimSize = end - start;

    for (int outer = 0; outer < totalOuter; outer++) {
      for (int d = start; d < end; d++) {
        final srcOffset = outer * dimSize * innerSize + d * innerSize;
        final dstOffset =
            outer * newDimSize * innerSize + (d - start) * innerSize;
        for (int inner = 0; inner < innerSize; inner++) {
          result.data[dstOffset + inner] = data[srcOffset + inner];
        }
      }
    }
    return result;
  }

  // ─── Reshape / View ─────────────────────────────────────────────────

  /// Reshape the tensor to a new shape. -1 infers that dimension.
  Tensor reshape(List<int> newShape) {
    final ns = List<int>.from(newShape);
    int inferIdx = -1;
    int known = 1;
    for (int i = 0; i < ns.length; i++) {
      if (ns[i] == -1) {
        assert(inferIdx == -1, 'Only one dimension can be -1');
        inferIdx = i;
      } else {
        known *= ns[i];
      }
    }
    if (inferIdx >= 0) {
      ns[inferIdx] = size ~/ known;
    }
    assert(_productOfShape(ns) == size,
        'Cannot reshape ${shape} to $ns (size $size vs ${_productOfShape(ns)})');
    return Tensor(Float32List.fromList(data), ns);
  }

  /// Permute dimensions. E.g., (0, 2, 1) transposes last two dims.
  Tensor permute(List<int> order) {
    assert(order.length == ndim);
    final newShape = [for (int i in order) shape[i]];
    final newStrides = [for (int i in order) strides[i]];
    final result = Tensor.zeros(newShape);
    final resultStrides = _computeStrides(newShape);

    final indices = List<int>.filled(ndim, 0);
    for (int flatIdx = 0; flatIdx < size; flatIdx++) {
      // Compute source offset from indices using old strides
      int srcOffset = 0;
      for (int d = 0; d < ndim; d++) {
        srcOffset += indices[d] * newStrides[d];
      }
      // Compute dest offset using new strides
      int dstOffset = 0;
      for (int d = 0; d < ndim; d++) {
        dstOffset += indices[d] * resultStrides[d];
      }
      result.data[dstOffset] = data[srcOffset];

      // Increment indices
      for (int d = ndim - 1; d >= 0; d--) {
        indices[d]++;
        if (indices[d] < newShape[d]) break;
        indices[d] = 0;
      }
    }
    return result;
  }

  /// Transpose: swap two dimensions.
  Tensor transpose(int dim0, int dim1) {
    final order = List<int>.generate(ndim, (i) => i);
    order[dim0] = dim1;
    order[dim1] = dim0;
    return permute(order);
  }

  /// Add a dimension of size 1 at the given position.
  Tensor unsqueeze(int dim) {
    if (dim < 0) dim = ndim + 1 + dim;
    final newShape = List<int>.from(shape);
    newShape.insert(dim, 1);
    return reshape(newShape);
  }

  /// Remove a dimension of size 1 at the given position.
  Tensor squeeze([int? dim]) {
    if (dim != null) {
      assert(shape[dim] == 1, 'Can only squeeze dim of size 1');
      final newShape = List<int>.from(shape);
      newShape.removeAt(dim);
      if (newShape.isEmpty) newShape.add(1);
      return reshape(newShape);
    }
    final newShape = shape.where((s) => s != 1).toList();
    if (newShape.isEmpty) newShape.add(1);
    return reshape(newShape);
  }

  /// Flatten to a 1D tensor.
  Tensor flatten() => reshape([size]);

  /// Expand a size-1 dimension to the given size (broadcast).
  Tensor expand(List<int> newShape) {
    assert(newShape.length == ndim);
    final result = Tensor.zeros(newShape);
    _broadcastCopy(this, result);
    return result;
  }

  /// Repeat along each dimension.
  Tensor repeat(List<int> times) {
    assert(times.length == ndim);
    final newShape = <int>[];
    for (int i = 0; i < ndim; i++) {
      newShape.add(shape[i] * times[i]);
    }
    final result = Tensor.zeros(newShape);

    final indices = List<int>.filled(ndim, 0);
    for (int flatIdx = 0; flatIdx < result.size; flatIdx++) {
      int srcOffset = 0;
      for (int d = 0; d < ndim; d++) {
        srcOffset += (indices[d] % shape[d]) * strides[d];
      }
      result.data[flatIdx] = data[srcOffset];

      for (int d = ndim - 1; d >= 0; d--) {
        indices[d]++;
        if (indices[d] < newShape[d]) break;
        indices[d] = 0;
      }
    }
    return result;
  }

  /// Concatenate a list of tensors along a given dimension.
  static Tensor cat(List<Tensor> tensors, [int dim = 0]) {
    if (tensors.length == 1) return tensors[0];
    final ndim = tensors[0].ndim;
    if (dim < 0) dim = ndim + dim;

    // Compute output shape
    final outShape = List<int>.from(tensors[0].shape);
    for (int i = 1; i < tensors.length; i++) {
      outShape[dim] += tensors[i].shape[dim];
    }

    final result = Tensor.zeros(outShape);
    int offset = 0;
    final outerDims = outShape.sublist(0, dim);
    final outerSize = outerDims.isEmpty ? 1 : _productOfShape(outerDims);
    final innerSize =
        dim + 1 < ndim ? _productOfShape(outShape.sublist(dim + 1)) : 1;
    final outDimStride = outShape[dim] * innerSize;

    for (final t in tensors) {
      final tDimSize = t.shape[dim];
      for (int outer = 0; outer < outerSize; outer++) {
        for (int d = 0; d < tDimSize; d++) {
          final srcStart = outer * tDimSize * innerSize + d * innerSize;
          final dstStart = outer * outDimStride + (offset + d) * innerSize;
          for (int inner = 0; inner < innerSize; inner++) {
            result.data[dstStart + inner] = t.data[srcStart + inner];
          }
        }
      }
      offset += tDimSize;
    }
    return result;
  }

  // ─── Element-wise Operations ────────────────────────────────────────

  Tensor operator +(Tensor other) => _elementWise(other, (a, b) => a + b);
  Tensor operator -(Tensor other) => _elementWise(other, (a, b) => a - b);
  Tensor operator *(Tensor other) => _elementWise(other, (a, b) => a * b);
  Tensor operator /(Tensor other) => _elementWise(other, (a, b) => a / b);

  /// Add a scalar to all elements.
  Tensor addScalar(double s) => map((x) => x + s);

  /// Multiply all elements by a scalar.
  Tensor mulScalar(double s) => map((x) => x * s);

  /// Divide all elements by a scalar.
  Tensor divScalar(double s) => map((x) => x / s);

  /// Apply a function to each element.
  Tensor map(double Function(double) fn) {
    final result = Float32List(size);
    for (int i = 0; i < size; i++) {
      result[i] = fn(data[i]);
    }
    return Tensor(result, List<int>.from(shape));
  }

  /// Element-wise power.
  Tensor pow(double exponent) => map((x) => math.pow(x, exponent).toDouble());

  /// Element-wise square root.
  Tensor sqrt() => map((x) => math.sqrt(x));

  /// Element-wise absolute value.
  Tensor abs() => map((x) => x.abs());

  /// Clamp values to [minVal, maxVal].
  Tensor clamp(double minVal, double maxVal) =>
      map((x) => x.clamp(minVal, maxVal));

  /// Element-wise negation.
  Tensor neg() => map((x) => -x);

  /// Element-wise GELU activation.
  Tensor gelu() {
    const sqrt2 = 1.4142135623730951;
    return map((x) => 0.5 * x * (1.0 + _erf(x / sqrt2)));
  }

  /// Element-wise ReLU activation.
  Tensor relu() => map((x) => x > 0 ? x : 0.0);

  /// Element-wise sigmoid.
  Tensor sigmoid() => map((x) => 1.0 / (1.0 + math.exp(-x)));

  /// Element-wise tanh.
  Tensor tanh() => map((x) {
        final e2x = math.exp(2.0 * x);
        return (e2x - 1.0) / (e2x + 1.0);
      });

  // ─── Reduction Operations ───────────────────────────────────────────

  /// Sum all elements.
  double sumAll() {
    double s = 0.0;
    for (int i = 0; i < size; i++) {
      s += data[i];
    }
    return s;
  }

  /// Mean of all elements.
  double meanAll() => sumAll() / size;

  /// Max of all elements.
  double maxAll() {
    double m = data[0];
    for (int i = 1; i < size; i++) {
      if (data[i] > m) m = data[i];
    }
    return m;
  }

  /// Argmax over all elements.
  int argmax() {
    int idx = 0;
    double m = data[0];
    for (int i = 1; i < size; i++) {
      if (data[i] > m) {
        m = data[i];
        idx = i;
      }
    }
    return idx;
  }

  /// Sum over a given dimension, keeping the dimension (size 1).
  Tensor sum(int dim, {bool keepDim = false}) {
    if (dim < 0) dim = ndim + dim;
    final outShape = List<int>.from(shape);
    outShape[dim] = 1;
    final result = Tensor.zeros(outShape);

    final outerSize = _productOfShape(shape.sublist(0, dim));
    final dimSize = shape[dim];
    final innerSize =
        dim + 1 < ndim ? _productOfShape(shape.sublist(dim + 1)) : 1;

    for (int outer = 0; outer < outerSize; outer++) {
      for (int inner = 0; inner < innerSize; inner++) {
        double s = 0.0;
        for (int d = 0; d < dimSize; d++) {
          s += data[outer * dimSize * innerSize + d * innerSize + inner];
        }
        result.data[outer * innerSize + inner] = s;
      }
    }
    if (!keepDim) {
      return result.squeeze(dim);
    }
    return result;
  }

  /// Mean over a given dimension.
  Tensor mean(int dim, {bool keepDim = false}) {
    final s = sum(dim, keepDim: keepDim);
    return s.divScalar(shape[dim].toDouble());
  }

  /// Max over a given dimension.
  Tensor maxDim(int dim, {bool keepDim = false}) {
    if (dim < 0) dim = ndim + dim;
    final outShape = List<int>.from(shape);
    outShape[dim] = 1;
    final result = Tensor.zeros(outShape);

    final outerSize = _productOfShape(shape.sublist(0, dim));
    final dimSize = shape[dim];
    final innerSize =
        dim + 1 < ndim ? _productOfShape(shape.sublist(dim + 1)) : 1;

    for (int outer = 0; outer < outerSize; outer++) {
      for (int inner = 0; inner < innerSize; inner++) {
        double m = data[outer * dimSize * innerSize + inner];
        for (int d = 1; d < dimSize; d++) {
          final v = data[outer * dimSize * innerSize + d * innerSize + inner];
          if (v > m) m = v;
        }
        result.data[outer * innerSize + inner] = m;
      }
    }
    if (!keepDim) {
      return result.squeeze(dim);
    }
    return result;
  }

  /// Softmax over a given dimension.
  Tensor softmax(int dim) {
    if (dim < 0) dim = ndim + dim;
    final maxVals = maxDim(dim, keepDim: true);
    final shifted = this - maxVals.expand(shape);
    final exps = shifted.map((x) => math.exp(x));
    final sumExps = exps.sum(dim, keepDim: true);
    return exps / sumExps.expand(shape);
  }

  /// Log-softmax over a given dimension.
  Tensor logSoftmax(int dim) {
    final sm = softmax(dim);
    return sm.map((x) => math.log(x + 1e-10));
  }

  // ─── Matrix Operations ─────────────────────────────────────────────

  /// Matrix multiplication for 2D tensors.
  ///
  /// [this] is (M, K) and [other] is (K, N), result is (M, N).
  Tensor matmul(Tensor other) {
    if (ndim == 2 && other.ndim == 2) {
      return _matmul2d(this, other);
    }
    if (ndim >= 3 && other.ndim == 2) {
      return _batchMatmul2d(this, other);
    }
    if (ndim >= 3 && other.ndim >= 3) {
      return _batchMatmulBoth(this, other);
    }
    throw ArgumentError(
        'matmul not supported for shapes $shape and ${other.shape}');
  }

  static Tensor _matmul2d(Tensor a, Tensor b) {
    final m = a.shape[0];
    final k = a.shape[1];
    final n = b.shape[1];
    assert(k == b.shape[0], 'Inner dims must match: $k vs ${b.shape[0]}');

    final result = Float32List(m * n);
    for (int i = 0; i < m; i++) {
      final rowOffset = i * k;
      for (int j = 0; j < n; j++) {
        double sum = 0.0;
        for (int p = 0; p < k; p++) {
          sum += a.data[rowOffset + p] * b.data[p * n + j];
        }
        result[i * n + j] = sum;
      }
    }
    return Tensor(result, [m, n]);
  }

  /// Batch matmul: (..., M, K) x (K, N) → (..., M, N)
  static Tensor _batchMatmul2d(Tensor a, Tensor b) {
    final batchShape = a.shape.sublist(0, a.ndim - 2);
    final m = a.shape[a.ndim - 2];
    final k = a.shape[a.ndim - 1];
    final n = b.shape[1];
    assert(k == b.shape[0]);

    final batchSize = _productOfShape(batchShape);
    final matSize = m * k;
    final outMatSize = m * n;
    final outData = Float32List(batchSize * outMatSize);

    for (int batch = 0; batch < batchSize; batch++) {
      final aOffset = batch * matSize;
      for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
          double sum = 0.0;
          for (int p = 0; p < k; p++) {
            sum += a.data[aOffset + i * k + p] * b.data[p * n + j];
          }
          outData[batch * outMatSize + i * n + j] = sum;
        }
      }
    }
    return Tensor(outData, [...batchShape, m, n]);
  }

  /// Batch matmul: (..., M, K) x (..., K, N) → (..., M, N)
  static Tensor _batchMatmulBoth(Tensor a, Tensor b) {
    final m = a.shape[a.ndim - 2];
    final k = a.shape[a.ndim - 1];
    final n = b.shape[b.ndim - 1];
    assert(k == b.shape[b.ndim - 2]);

    final aBatchShape = a.shape.sublist(0, a.ndim - 2);
    final bBatchShape = b.shape.sublist(0, b.ndim - 2);
    // Broadcast batch dimensions
    final batchShape = _broadcastShapes(aBatchShape, bBatchShape);
    final batchSize = _productOfShape(batchShape);
    final aBatchSize = _productOfShape(aBatchShape);
    final bBatchSize = _productOfShape(bBatchShape);

    final aMatSize = m * k;
    final bMatSize = k * n;
    final outMatSize = m * n;
    final outData = Float32List(batchSize * outMatSize);

    for (int batch = 0; batch < batchSize; batch++) {
      final aBatch = batch % aBatchSize;
      final bBatch = batch % bBatchSize;
      final aOffset = aBatch * aMatSize;
      final bOffset = bBatch * bMatSize;

      for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
          double sum = 0.0;
          for (int p = 0; p < k; p++) {
            sum += a.data[aOffset + i * k + p] * b.data[bOffset + p * n + j];
          }
          outData[batch * outMatSize + i * n + j] = sum;
        }
      }
    }
    return Tensor(outData, [...batchShape, m, n]);
  }

  // ─── Utility ────────────────────────────────────────────────────────

  /// Create a deep copy.
  Tensor clone() => Tensor(Float32List.fromList(data), List<int>.from(shape));

  /// Convert to a nested Dart list.
  dynamic toList() {
    if (ndim == 1) {
      return List<double>.from(data);
    }
    return List.generate(shape[0], (i) => this[i].toList());
  }

  @override
  String toString() {
    if (size <= 20) {
      return 'Tensor(shape: $shape, data: ${data.toList()})';
    }
    final first = data.sublist(0, 5).toList();
    final last = data.sublist(size - 5).toList();
    return 'Tensor(shape: $shape, data: [$first ... $last])';
  }

  // ─── Private Helpers ────────────────────────────────────────────────

  Tensor _elementWise(Tensor other, double Function(double, double) op) {
    if (_listsEqual(shape, other.shape)) {
      // Same shape — fast path
      final result = Float32List(size);
      for (int i = 0; i < size; i++) {
        result[i] = op(data[i], other.data[i]);
      }
      return Tensor(result, List<int>.from(shape));
    }
    // Broadcasting
    final outShape = _broadcastShapes(shape, other.shape);
    final outSize = _productOfShape(outShape);
    final result = Float32List(outSize);

    final aStrides = _broadcastStrides(shape, outShape);
    final bStrides = _broadcastStrides(other.shape, outShape);

    final indices = List<int>.filled(outShape.length, 0);
    for (int i = 0; i < outSize; i++) {
      int aIdx = 0, bIdx = 0;
      for (int d = 0; d < outShape.length; d++) {
        aIdx += indices[d] * aStrides[d];
        bIdx += indices[d] * bStrides[d];
      }
      result[i] = op(data[aIdx], other.data[bIdx]);

      for (int d = outShape.length - 1; d >= 0; d--) {
        indices[d]++;
        if (indices[d] < outShape[d]) break;
        indices[d] = 0;
      }
    }
    return Tensor(result, outShape);
  }

  static void _broadcastCopy(Tensor src, Tensor dst) {
    final outShape = dst.shape;
    final srcStrides = _broadcastStrides(src.shape, outShape);
    final indices = List<int>.filled(outShape.length, 0);
    for (int i = 0; i < dst.size; i++) {
      int srcIdx = 0;
      for (int d = 0; d < outShape.length; d++) {
        srcIdx += indices[d] * srcStrides[d];
      }
      dst.data[i] = src.data[srcIdx];

      for (int d = outShape.length - 1; d >= 0; d--) {
        indices[d]++;
        if (indices[d] < outShape[d]) break;
        indices[d] = 0;
      }
    }
  }

  static int _productOfShape(List<int> shape) {
    if (shape.isEmpty) return 0;
    int p = 1;
    for (final s in shape) {
      p *= s;
    }
    return p;
  }

  static List<int> _computeStrides(List<int> shape) {
    final strides = List<int>.filled(shape.length, 1);
    for (int i = shape.length - 2; i >= 0; i--) {
      strides[i] = strides[i + 1] * shape[i + 1];
    }
    return strides;
  }

  static List<int> _broadcastShapes(List<int> a, List<int> b) {
    final maxLen = math.max(a.length, b.length);
    final result = List<int>.filled(maxLen, 0);
    for (int i = 0; i < maxLen; i++) {
      final ai = i < maxLen - a.length ? 1 : a[i - (maxLen - a.length)];
      final bi = i < maxLen - b.length ? 1 : b[i - (maxLen - b.length)];
      if (ai != bi && ai != 1 && bi != 1) {
        throw ArgumentError('Cannot broadcast shapes $a and $b');
      }
      result[i] = math.max(ai, bi);
    }
    return result;
  }

  static List<int> _broadcastStrides(List<int> srcShape, List<int> outShape) {
    final srcStrides = _computeStrides(srcShape);
    final result = List<int>.filled(outShape.length, 0);
    final offset = outShape.length - srcShape.length;
    for (int i = 0; i < srcShape.length; i++) {
      result[offset + i] = srcShape[i] == 1 ? 0 : srcStrides[i];
    }
    return result;
  }

  static bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Error function approximation for GELU.
  static double _erf(double x) {
    final a1 = 0.254829592;
    final a2 = -0.284496736;
    final a3 = 1.421413741;
    final a4 = -1.453152027;
    final a5 = 1.061405429;
    final p = 0.3275911;

    final sign = x < 0 ? -1.0 : 1.0;
    final absX = x.abs();
    final t = 1.0 / (1.0 + p * absX);
    final y = 1.0 -
        (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) *
            t *
            math.exp(-absX * absX);
    return sign * y;
  }

  /// Create a causal (lower triangular) attention mask.
  static Tensor causalMask(int size) {
    final data = Float32List(size * size);
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        data[i * size + j] = j <= i ? 0.0 : -1e9;
      }
    }
    return Tensor(data, [size, size]);
  }

  /// Create a padding mask (1 for valid, 0 for padding).
  static Tensor paddingMask(List<int> lengths, int maxLen) {
    final batchSize = lengths.length;
    final data = Float32List(batchSize * maxLen);
    for (int b = 0; b < batchSize; b++) {
      for (int i = 0; i < maxLen; i++) {
        data[b * maxLen + i] = i < lengths[b] ? 1.0 : 0.0;
      }
    }
    return Tensor(data, [batchSize, maxLen]);
  }
}
