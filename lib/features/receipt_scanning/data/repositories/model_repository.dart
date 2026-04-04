import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/failures.dart';
import '../models/app_config.dart';

abstract class ModelRepository {
  Future<Either<Failure, AppConfig?>> getLatestModelConfig();
}

class SupabaseModelRepository implements ModelRepository {
  final SupabaseClient client;

  SupabaseModelRepository(this.client);

  @override
  Future<Either<Failure, AppConfig?>> getLatestModelConfig() async {
    try {
      final response = await client
          .from('app_config')
          .select()
          .eq('key', 'latest_model_version')
          .maybeSingle();

      if (response == null) {
        return const Right(null);
      }

      final config = AppConfig.fromJson(response);
      return Right(config);
    } catch (e) {
      // Return unexpected failure but allow app to continue with local model
      return const Left(ServerFailure()); 
    }
  }
}
