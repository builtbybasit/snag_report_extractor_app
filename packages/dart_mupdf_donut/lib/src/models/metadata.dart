/// PDF document metadata, equivalent to PyMuPDF's `doc.metadata`.
class PdfMetadata {
  String? title;
  String? author;
  String? subject;
  String? keywords;
  String? creator;
  String? producer;
  String? creationDate;
  String? modDate;
  String? format;
  String? encryption;
  bool trapped;

  PdfMetadata({
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.creator,
    this.producer,
    this.creationDate,
    this.modDate,
    this.format,
    this.encryption,
    this.trapped = false,
  });

  factory PdfMetadata.empty() => PdfMetadata();

  Map<String, String?> toMap() => {
        'title': title,
        'author': author,
        'subject': subject,
        'keywords': keywords,
        'creator': creator,
        'producer': producer,
        'creationDate': creationDate,
        'modDate': modDate,
        'format': format,
        'encryption': encryption,
        'trapped': trapped ? 'True' : 'False',
      };

  @override
  String toString() =>
      'PdfMetadata(title: $title, author: $author, pages: format=$format)';
}
