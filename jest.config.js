const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver', '<rootDir>/docs'],
    testPathIgnorePatterns: ['<rootDir>/node_modules/', '<rootDir>/docs/']
};
