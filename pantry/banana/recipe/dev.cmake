cooking_ingredient (Durian
  CMAKE_ARGS -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
  EXTERNAL_PROJECT_ARGS
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/extern/durian)

cooking_ingredient (Carrot
  COOKING_RECIPE dev
  REQUIRES Durian
  EXTERNAL_PROJECT_ARGS
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/extern/carrot)