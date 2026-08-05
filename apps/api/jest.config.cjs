module.exports = {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: '.',
  testRegex: '.*\\.(spec|integration-spec|e2e-spec)\\.ts$',
  transform: {
    '^.+\\.(t|j)s$': ['ts-jest', {
      tsconfig: {
        module: 'commonjs',
        types: ['jest', 'node'],
      },
      isolatedModules: true,
    }],
  },
  testEnvironment: 'node',
  collectCoverageFrom: ['src/**/*.(t|j)s'],
};
