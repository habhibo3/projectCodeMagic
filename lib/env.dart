enum Env { staging, prod }

final Env currentEnv = const String.fromEnvironment('ENV') == 'staging' ? Env.staging : Env.prod;
