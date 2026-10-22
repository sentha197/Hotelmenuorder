enum FeedbackError {
  missingRating('Please select a star rating.'),
  ratingOutOfRange('Ratings go from 1 to 5 stars.'),
  commentTooLong('Feedback can be at most 300 characters.');

  const FeedbackError(this.message);

  final String message;
}

class FeedbackException implements Exception {
  const FeedbackException(this.error);

  final FeedbackError error;

  @override
  String toString() => 'FeedbackException(${error.name})';
}

/// A guest's rating of an order.
class OrderFeedback {
  const OrderFeedback({
    required this.rating,
    required this.comment,
    required this.submittedAt,
  });

  factory OrderFeedback.fromJson(Map<String, dynamic> json) => OrderFeedback(
    rating: json['rating'] as int,
    comment: json['comment'] as String? ?? '',
    submittedAt: DateTime.parse(json['submittedAt'] as String),
  );

  static const maxCommentLength = 300;

  final int rating;
  final String comment;
  final DateTime submittedAt;

  /// Returns null when the input is valid.
  static FeedbackError? validate({
    required int rating,
    required String comment,
  }) {
    if (rating == 0) return FeedbackError.missingRating;
    if (rating < 1 || rating > 5) return FeedbackError.ratingOutOfRange;
    if (comment.trim().length > maxCommentLength) {
      return FeedbackError.commentTooLong;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'rating': rating,
    'comment': comment,
    'submittedAt': submittedAt.toIso8601String(),
  };
}
